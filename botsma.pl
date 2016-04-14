use strict;
use utf8;
use vars qw($VERSION %IRSSI);

use Irssi qw(signal_add timeout_add);
use Irssi::TextUI;

use LWP::Simple qw(:DEFAULT $ua);

use DateTime::Format::Strptime;

use Botsma::Common;
use Botsma::WStations;
use Botsma::Encoding;

use Storable;

use JSON;

use warnings;

$VERSION = '0.5';
%IRSSI =
(
	authors => 'Jorrit Tijben, Nieko Maatjes',
	contact => 'jorrit@tijben.net',
	name => 'Furbie Imposter',
	description => 'Started out as a cheap alternative for some Furbie ' .
	               'commands which were blatantly stolen from ' .
                   'http://furbie.net/source/ ... ' .
                   'Over time new and original commands were added.',
	license => 'GPL',
);

# Strptime with pattern to 'convert' a string representation of time to a
# DateTime object.
my $Strp = new DateTime::Format::Strptime(
	pattern => '%d-%m-%y %T',
);

# The date and time of the last message that was seen by the P2000 announcer.
my $lasttime = '';

# Read the BOFH file into memory.
my @excuse;

if (open(F, Irssi::get_irssi_dir . '/scripts/excuses'))
{
	@excuse = <F>;
}
else
{
	print 'Kon de excuse-file niet openen. Ironisch!';
}

# Read users preferences from disk.
my %users = ();
if (-e Irssi::get_irssi_dir . '/scripts/users') {
	%users = %{retrieve(Irssi::get_irssi_dir . '/scripts/users')};
}

# Read the seen images and videos from disk.
my %links = ();
if (-e Irssi::get_irssi_dir . '/scripts/links') {
	%links = %{retrieve(Irssi::get_irssi_dir . '/scripts/links')};
}

# Possible user settings, with default values. Note that these default values
# are actually implemented/harcoded in the subroutines, so they're just used
# informatively here.
my %settings =
(
	wstation => 'Twente',
	location => 'Enschede',
	regen => 'utf-8',
);

my %locations =
(
	campus =>
	{
		lat => 52.247195,
		lon => 6.848019,
	}
);

my %whatStatus =
(
	site => undef,
	irc => undef,
	tracker => undef,
);

# Parse private messages (queries) the client/bot receives. If it's a bot
# command, call the appropriate function. Otherwise do nothing.
#
# Parameters:
# $server The server from which the message originated.
# $msg The entire message.
# $nick The nickname that typed the message.
# $address User or server host? Ignored anyway.
sub _parsePrivate
{
	my ($server, $msg, $nick, $address) = @_;
	
	my $reply = '';

	# Empty $target argument.
	$reply = _command($server, $msg, $nick, $address, '');

	# Send the (nonempty) reply to the target nick.
	if ($reply)
	{
		my $part;
		foreach $part (split(/\\n/, $reply))
		{
			# Ugly way to sleep half a second
			# select(undef, undef, undef, 0.5);
			$server->command('msg ' . $nick . ' ' . $part);
			$server->command('wait 50');
		}
	}
}

# Parse public messages the client/bot receives. Call the appropriate functions
# to do something useful with them. For example, if messages are prefixed by
# the bot's name and a colon, like 'Botsma:', it means that someone requested a
# command.
#
# Messages containing YouTube or Vimeo links will announce the title, and
# messages like 's/pattern/replace/i' will be handed off to a sed-like
# function. 
#
# More functions can and will be added...
# 
# Parameters:
# $server The server from which the message originated.
# $msg The entire message.
# $nick The nickname that typed the message.
# $address User or server host? Ignored anyway.
# $target The IRC channel or IRC query nickname.
sub _parsePublic
{
	my ($server, $msg, $nick, $address, $target) = @_;

	my $mynick;
	my $reply = '';

	$mynick = $server->{nick};

	# When the nick is empty, it's probably ourselves.
	#### $nick = $mynick if ($nick eq '');

	if ($nick eq "eugen-ia") {
		return;
	}

	if ($msg =~ m/^$mynick:/i)
	{
		# Strip the prefix.
		$msg =~ s/$mynick:\s*//i;
		$reply = _command($server, $msg, $nick, $address, $target);
	}
	elsif (($target eq "#inter-actief" || $target eq '#testchan') and
	       $msg =~ m#(https?://.*youtube.*/watch\?.*v=|https?://youtu\.be/)([A-Za-z0-9_\-]+)#)
	{
		$reply = _youtube($2, $nick);
	}
	elsif (($target eq '#inter-actief' || $target eq "#testchan") and
	       $msg =~ m#https?://.*vimeo\.com/(\d+)#)
	{
		$reply = _vimeo($1, $nick);
	}
	elsif (($target eq '#inter-actief' || $target eq "#testchan") and
	       $msg =~ m#https?://.*imgur\.com/(a/|gallery/)?([A-Za-z0-9]+)(\..+)?#)
	{
		$reply = _imgur($1, $2, $nick);
	}
	# Any URL.
	# Modified regex from John Gruber:
	# http://daringfireball.net/2009/11/liberal_regex_for_matching_urls
	# This is far from perfect but should work in most cases.
	elsif (($target eq '#inter-actief' || $target eq "#testchan") and
	       $msg =~ m#\b(([\w-]+://?(www[.])?|www[.])([^\s()<>]+(?:\([\w\d]+\)|([^[:punct:]\s])))/?)#)
	{
		my $url = $4;

		if (exists $links{$url})
		{
			$reply = join('', 'Oud! (', $links{$url}, ')');
		}
		else
		{
			my $now = DateTime->
				now(time_zone => 'Europe/Amsterdam')->
				strftime('%F %R');
			print 'Saving URL ', $url;
			$links{$url} = join(' op ', $nick, $now);
		}
	}
	# Someone is trying to substitute (correct) his previous sentence.
	#
	# With optional last separator (but note that it gives problems with,
	# for example: s/old/newi because that's interpreted as s/old/new/i
	elsif (($target eq "#inter-actief" || $target eq "#testchan") and
		   $msg =~ m/^s([\/|#.:;])(.*?)\1(.*?)\1?([gi]*)$/)
	{
		$reply = _sed($2, $3, $4, $nick, $target);
	}

	# Send the reply to the target (channel/nick), if it exists.
	if ($reply)
	{
		my $part;
		foreach $part (split(/\\n/, $reply))
		{
			# Ugly way to sleep half a second
			# select(undef, undef, undef, 0.5);
			$server->command('msg '.$target.' '.$part);
			$server->command('wait 50');
		}
	}
}

sub _command
{
	my ($server, $msg, $nick, $address, $target, $mynick) = @_;

	my ($cmd, $params, $cmdref);
	my $reply = '';

	# Remove trailing whitespace.
	$msg =~ s/\s+$//;
	# Parse the line into the command and parameters.
	($cmd, $params) = split(/\s+/, $msg, 2);
	# Be case insensitive.
	$cmd = lc $cmd;

	# Don't execute 'internal' subroutines.
	if (index($cmd, '_') == 0)
	{
		print 'Internal!';
		return '';
	}

	if (Botsma::Encoding::encoding_exists($cmd))
	{
		$reply = _command($server, $params, $nick, $address, $target, $mynick);
		if ($reply)
		{
			$reply = Botsma::Encoding::encode($cmd, $reply);
		}
		else
		{
			# geen bestaand commando, gewoon hele regel encoden
			$reply = Botsma::Encoding::encode($cmd, $params);
		}
	}
	else
	{
		# $reply = Irssi::Script::botsma->$cmd($server, $params, $nick,
		# $address, $target); would cause 'Irssi::Script::botsma to be
		# the first argument to $cmd...  The following bypasses that by
		# making use of the can() UNIVERSAL function.
		eval
		{
			# Use the subroutine with name $cmd from either our own package
			# or from Botsma::Common.
			if ($cmdref = __PACKAGE__->can($cmd) or
				$cmdref = Botsma::Common->can($cmd))
			{
				$reply = $cmdref->($server, $params, $nick, $address, $target);
			}
			# Ehm... &($cmd) works too?
		};
		if ($@)
		{
			#warn $@;
			# Could be other errors though...
			# $server->command('msg '.$target.' Dat commando moet Dutchy nog implementeren.');
		}
	}

	return $reply;
}

# Look up the video title for a YouTube hash.
#
# Parameters:
# $hash A string with a valid video hash.
# $nick The nick who posted the video link.
#
# Returns:
# A string with the video title, or the empty string on error.
sub _youtube
{
	my ($hash, $nick) = @_;

	my ($url, $decoded);
	my $reply = '';

	# Did we see this video before?
	if (exists $links{'YouTube' . $hash})
	{
		return join('', 'Oud! (', $links{'YouTube' . $hash}, ')');
	}

	# We construct the URL manually based on the hash, because YouTube
	# doesn't seem to like URLs with, for example,
	# 'feature=player_embedded' in it. Ugh.
	$url = get join('', 'http://www.youtube.com/oembed?url=',
	                    'http://www.youtube.com/watch?v=', $hash,
	                    '&format=json');
	
	# Ignore exceptions from JSON.
	eval
	{
		$decoded = decode_json($url);
		$reply = $decoded->{title};
	};

	# Remember this hash so we can shout 'Oud!' when the video has been posted
	# before.
	my $now = DateTime->
		now(time_zone => 'Europe/Amsterdam')->
		strftime('%F %R');
	$links{'YouTube' . $hash} = join(' op ', $nick, $now);

	if ($reply)
	{
		return join(' ', '[YouTube]', $reply);
	}
}

# Look up the video title for a Vimeo hash.
#
# Parameters:
# $hash A string with a valid video hash.
# $nick The nick who posted the video link.
#
# Returns:
# A string with the video title, or the empty string on error.
sub _vimeo
{
	my ($hash, $nick) = @_;

	my ($url, $decoded);
	my $reply = '';

	# Did we see this video before?
	if (exists $links{'Vimeo' . $hash})
	{
		return join('', 'Oud! (', $links{'Vimeo' . $hash}, ')');
	}

	# Apparently Vimeo dislikes Perl's LWP... 
	$ua->agent('Botsma');
	$url = get join('', 'http://vimeo.com/api/oembed.json?url=',
	                    'http://vimeo.com/', $hash);

	# Ignore exceptions from JSON.
	eval
	{
		$decoded = decode_json($url);
		$reply = join(': ', $decoded->{title}, $decoded->{description});
		# Description can be quite large... strip to 100 characters or
		# something?
		$reply = join('', substr($reply, 0, 100), '...');
	};

	# Remember this hash so we can shout 'Oud!' when the video has been posted
	# before.
	my $now = DateTime->
		now(time_zone => 'Europe/Amsterdam')->
		strftime('%F %R');
	$links{'Vimeo' . $hash} = join(' op ', $nick, $now);

	if ($reply)
	{
		return join(' ', '[Vimeo]', $reply);
	}
}

# Look up the title for a imgur link
#
# Parameters:
# $a Whether this is an album or image.
# $hash An image or album hash.
# $nick The nick who posted the image link.
#
# Returns:
# A string with the image or album title, or the empty string on error.
sub _imgur
{
	my ($a, $hash, $nick) = @_;

	my ($url, $decoded);
	my $reply = '';

	# Did we see this image before?
	if (exists $links{'Imgur' . $hash})
	{
		return join('', 'Oud! (', $links{'Imgur' . $hash}, ')');
	}

	if (defined $a && $a eq 'a/')
	{
		$url = get join('', 'http://api.imgur.com/2/album/', $hash, '.json');
		eval
		{
			$decoded = decode_json($url);
			$reply = $decoded->{album}->{title};
			my $description = $decoded->{album}->{description};
			$reply = join(': ', $reply, $description) if $description;
		}
	}
	else
	{
		$url = get join('', 'http://api.imgur.com/2/image/', $hash, '.json');
		eval
		{
			$decoded = decode_json($url);
			$reply = $decoded->{image}->{image}->{title};
			if (not defined $reply) { $reply = ''; }
			my $caption = $decoded->{image}->{image}->{caption};
			$reply = join(': ', $reply, $caption) if $caption;
			$reply = join('', substr($reply, 0, 100), '...') if length $reply > 100;
		}
	}

	# Remember this hash so we can shout 'Oud!' when the image has been posted
	# before.
	my $now = DateTime->
		now(time_zone => 'Europe/Amsterdam')->
		strftime('%F %R');
	$links{'Imgur' . $hash} = join(' op ', $nick, $now);

	if ($reply)
	{
		return join(' ', '[Imgur]', $reply);
	}
}

# Provides a sed-like 'command' for people in some channels. For example, they
# can type 's/old/new' to correct their previous sentence.
#
# Parameters:
# $pattern A string with the search pattern.
# $replace A string with the replacement text.
# $flags Either 'i' for case insensitive search, or 'g' for global matching.
# $nick The nickname that initiated this sed search.
# $target The channel or query on which the substitution must be made.
#
# Returns:
# A string describing $nick did a substitution or corrected some other nick's
# sentence. This is followed by the substitution.
# If no substitution could be made, return an error.
# For undefined behaviour or other errors, the empty string is returned.
sub _sed
{
	my ($pattern, $replace, $flags, $nick, $target) = @_;

	my ($substWindow, $lines, $corrNick, $original, $substitution);
	my $reply = '';

	#$substWindow = Irssi::window_find_item("#inter-actief");
	$substWindow = Irssi::window_find_item($target);
	$lines = $substWindow->view()->get_lines();

	# Bah... there seems to be no other way way to search from the back.
	# Irssi::TextUI::TextBufferView has {startline} and {bottom_startline}
	# but they all reference the first line.
	# 
	# Now we first have to iterate through all the lines in the text buffer
	# before searching backwards.

	$lines = $lines->next() while defined $lines->next();

	# If I try it this way... $1 is not getting the right value :-(
	# Search for the last line $nick said.
	# while (defined $lines and not
	#	$lines->get_text(0) =~ m/\d\d:\d\d <[\s\@\+]$nick> (.*)$/)
	# {
	#	$lines = $lines->prev();
	# }

	while (defined $lines)
	{
		# \Q..\E should be safe...
		if ($lines->get_text(0) =~ m/\d\d:\d\d ( \* (\S+)|<[\s\@\+\&](.+?)>) (.*\Q$pattern\E.*)$/)
		{
			# Returns the variable that is defined.
			$corrNick = $2 // $3;
			$original = $4;

			last;
		}

		$lines = $lines->prev();
	}

	# If $lines is not defined now, it means the pattern didn't match.
	if (defined $lines)
	{
		$substitution = _substitute($pattern, $replace, $flags, $original);

		if ($substitution)
		{
			if ($corrNick eq $nick)
			{
				$reply = $nick." bedoelde: ".$substitution;
			}
			else
			{
				$reply = $nick." verbeterde ".$corrNick.": ".$substitution;
			}
		}
		else
		{
			$reply = sprintf('%s %s, %s, dat vervangt toch helemaal niks!',
							 aanhef(), $nick, scheldwoord());
		}
	}

	return $reply;
}

# Substitute a pattern in a string using the Perl substitute command.
# Allowed flags can be 'i' (case insensitive) or 'g' (global).
#
# Parameters:
# $pattern The pattern this the string $reply is searched for, and if found,
#          gets replaced by the replacement string $replace.
# $replace The replacement text in case the pattern matched.
# $flags Optional flags that influence the matching. Allowed flags for this
#        function are 'i' (case insensitive) and 'g' (global substitution).
# $reply The string on which a substitute will take place.
#
# Returns:
# The substituted string if there was a match, or an empty string ('') if
# there was no match.
sub _substitute
{
	my ($pattern, $replace, $flags, $reply) = @_;
	my $result;

	# Better not to leave this to the caller function.
	$pattern = quotemeta($pattern);

	# This isn't pretty and doesn't look pretty, but I can't think of a
	# better way at the moment. Extended patterns don't work for the 'g' flag.
	eval
	{
		if ($flags =~ m/g/)
		{
			if ($flags =~ m/i/)
			{
				$result = ($reply =~ s/$pattern/$replace/gi);
			}
			else
			{
				$result = ($reply =~ s/$pattern/$replace/g);
			}
		}
		elsif ($flags =~ m/i/)
		{
			$result = ($reply =~ s/$pattern/$replace/i);
		}
		else
		{
			$result = ($reply =~ s/$pattern/$replace/);
		}
	};
	# Someone on the internet
	# (https://www.socialtext.net/perl5/exception_handling) said using $@ like
	# this is dangerous.
	# See also http://search.cpan.org/~doy/Try-Tiny-0.11/lib/Try/Tiny.pm#BACKGROUND
	# We'll risk it.
	if ($@)
	{
		warn $@;
		return '';
	}

	# If there was no substitution, return an empty string, otherwise the new
	# string (with substitutions).	
	return ($result) ? $reply : '';
}

# Not even going to describe this :-)
sub dans
{
	my ($server, $params, $nick, $address, $target) = @_;
	return ':D\\-<\n:D|-<\n:D/-<\n:D|-<';
}

# Search p2000-online.net for emergency announcements on/around the University
# of Twente's campus.
#
# Forward new announcements to the #inter-actief channel on IRCnet.
sub p2000
{
	my
	(
		$url, $valid, $key, $value, $brandweer, $ambulance, $politie, $server,
		$part, $dt
	);

	my $msg = '';

	# Add mIRC-colours: Brandweer in red, Politie in blue, Ambulance in green.
	$brandweer = chr(03).'04Brandweer'.chr(03);
	$politie = chr(03).'12Politie'.chr(03);
	$ambulance = chr(03).'09Ambulance'.chr(03);

	my @streets = 
	(
		'universiteit', 'calslaan', 'campuslaan',
		'de hems', 'matenweg', 'witbreuksweg',
		'achterhorst', 'drienerbeeklaan', 'bosweg',
		'boerderijweg', 'de horst', 'de knepse',
		'de zul', 'drienerlolaan', 'hallenweg',
		'horstlindelaan', 'het ritke',
		'langenkampweg', 'oude drienerlo weg', 'oude horstlindeweg',
		'parallelweg noord', 'parallelweg zuid', 'reelaan',
		'van heeksbleeklaan', 'viermarkenweg', 'zomerdijksweg',
	);

	$url = get 'http://www.p2000-online.net/p2000.php?Brandweer=1&Ambulance=1&Politie=1&Twente=1&AutoRefresh=uit';

	# This is not fast ;-)
	foreach (@streets)
	{
		if ($url =~m#<tr><td class="DT">(\d\d-\d\d-\d\d)</td><td class="DT">(\d\d:\d\d:\d\d)</td><td class=".*">(\w*)</td><td class="Regio">Twente</td><td class=".*">(.*?\s$_\s.*ENSCHEDE.*?)</td></tr>#i)
		{
			# $1 is the date
			# $2 is the time
			# $3 is the type: Brandweer/Politie/Ambulance
			# $4 is the actual message
			# $& is the entire regex match

			# Is this announcement newer (later date) than the one we annouced last
			# time?
			#
			# Makes use of the fact that if left is true, right won't be evaluated
			# (left to right short-circuit evaluation).
			if ($lasttime eq '' ||
			    DateTime->compare($Strp->parse_datetime("$1 $2"), $lasttime) == 1)
			{
				$msg = $msg.$2.' '.$3.' '.$4.'\n';
				$lasttime = $Strp->parse_datetime("$1 $2");
			}
		}
	}

	if ($msg)
	{
		# Add the colours.
		$msg =~ s/Brandweer/$brandweer/g;
		$msg =~ s/Politie/$politie/g;
		$msg =~ s/Ambulance/$ambulance/g;

		# Send the annoucement to #inter-actief on IRCnet.
		$server = Irssi::server_find_tag('IRCnet');
		
		foreach $part (split(/\\n/, $msg))
		{
			$server->command('msg #inter-actief '.$part);
		}
	}
}

# Wrapper around the temp subroutine from Botsma::Common, to facilitate
# comparisons between weather stations for certain nicks/users.
#
# Parameters:
# $server Ignored.
# $params The name of the weather station which can be found at
#         http://www.knmi.nl/actueel/
# $nick The nickname that called this command.
# $address Ignored.
# $target Target channel, or nick in case of a /query, used to lookup a
#         nickname.
#
# Returns:
# Temperature of Twente or the supplied weather station or...
# Temperature difference between a users' preferred weather station and Twente
# or...
# An error message.
sub temp
{
	my ($server, $params, $nick, $address, $target) = @_;

	# Prefix. Currently only used to highlight a specific nick, if someone
	# supplied a nickname as an argument to this function.
	my $prefix = '';

	# Weather station of the user. Set by a nearest neighbour search from
	# the location setting, or directly from the weather station setting.
	my $userStation;

	# Temperature of the user's weather station, and the temperature of
	# Twente.
	my ($userTemp, $twenthe, $userTempColour, $twentheColour);

	# Set to 1 if someone wants to look up the temperature of a different
	# nickname.
	my $nickSearch = 0;

	# Explicit parameters? They can either be a nickname or a place. If it is
	# neither, directly pass it on to the function in Botsma::Common...
	if ($params)
	{
		# Is it a nickname?
		#
		# This line always generates a warning.
		# See http://bugs.irssi.org/index.php?do=details&task_id=242
		my $channel = $server->channel_find($target);

		if ($channel and $channel->nick_find($params))
		{
			$nickSearch = 1;
			$nick = $params;
			$prefix = join('', $params, ': ');
		}
		else
		{
			my $coords = place($server, $params, $nick, $address, $target);

			# Basically does the same as _checkPlace, but we want to take
			# different actions for when a city wasn't found at all, or when
			# multiple cities were found.
			if ($coords eq '')
			{
				return Botsma::Common::temp(@_);
			}
			elsif (!Botsma::Common::validcoords($server, $coords, $nick,
			                                    $address, $target))
			{
				return $coords;
			}
			else
			{
				$userStation = Botsma::WStations::nearest($coords);
			}
		}
	}

	# Look up the preferences of ourself if no parameters were supplied to the
	# temp function, or look up the preferences of a different nickname.
	if (!$params or $nickSearch)
	{
		# Some user explicitly stored a weather station preference.
		if (defined $users{$nick}{wstation})
		{
			$userStation = $users{$nick}{wstation};
		}
		# Some user has a location set. We will automatically determine the
		# nearest weather station, and show the difference with Twente (if
		# it's not Twente itself...).
		elsif (defined $users{$nick}{location})
		{
			# Replace $params with the user defined setting.
			$params = $users{$nick}{location};

			# Look up the coordinates of the given place. Return if the place
			# couldn't be found, or if multiple cities are found.
			my $coords = place($server, $params, $nick, $address, $target);

			# Check whether we got something other than coordinates and return
			# if this is the case. This should've been checked while saving the
			# preference, but we'll be extra sure...
			my $check;
			if ($check = _checkPlace($server, $coords, $nick,
									 $address, $target))
			{
				return $check;
			}

			$userStation = Botsma::WStations::nearest($coords);
		}
		# No weather station was supplied, and the user didn't have preference
		# settings. Just call Botsma::Common::temp and get the temperature for
		# the default weather station.
		else
		{
			$userTemp = Botsma::Common::temp(@_);
			$userTempColour = Botsma::Common::colourTemp($userTemp);
			return $userTempColour;
		}
	}

	# General section for when either:
	# - a nick, location or weather station was explicitly specified.
	# - location or wstation was set.

	$twenthe = Botsma::Common::temp($server, '', $nick,
	                                $address, $target);

	# Return the default Twente temperature, because the nearest
	# weather station turned out to be Twente.
	return join('', $prefix, Botsma::Common::colourTemp($twenthe)) if ($userStation eq 'Twente');

	# Otherwise continue and show the difference between the weather
	# station of the user and Twente.
	$userTemp = Botsma::Common::temp($server, $userStation, $nick,
	                                 $address, $target);
	
	return
		join(' ', 'Meetstation', $userStation, 'bestaat niet of is stuk.')
		unless $userTemp =~ s/ °C//;

	return
		join('', $prefix, Botsma::Common::colourTemp($userTemp), ' °C (', $userStation, ')\n',
		         'Kon de temperatuur niet vergelijken met Twente, ',
		         'aangezien dat weerstation wat brakjes lijkt.')
		unless $twenthe =~ s/ °C//;

	# If we didn't return up until this point, we have two valid
	# temperatures.
	my $difference = $userTemp - $twenthe;
	$difference = sprintf('%.1f', $difference);

	my ($warmth);

	if ($difference > 0)
	{
		$warmth = abs($difference) . ' graden warmer dan';
	}
	elsif ($difference < 0)
	{
		$warmth = abs($difference) . ' graden kouder dan';
	}
	else
	{
		$warmth = 'even warm als';
	}

	$twentheColour = Botsma::Common::colourTemp($twenthe);
	$userTempColour = Botsma::Common::colourTemp($userTemp);
	
	return join('', $prefix, $userStation, ' (', $userTempColour, ' °C) is ',
	                $warmth, ' Twente (', $twentheColour, ' °C)');
}

# Get a Bastard Operator From Hell excuse.
#
# Returns:
# A random line from the BOFH excuse file.
sub bofh
{
	#
	## (c) 1994-2000 Jeff Ballard.
	##
	# http://pages.cs.wisc.edu/~ballard/bofh/
	
	# No need to call srand anymore.
	# srand(time);

	return $excuse[rand(scalar(@excuse))];
}

# Simple wrapper around Botsma::Common functions that accept coordinates. For
# now, these are 'regen' and 'zon'.
#
# The wrapper exists so we can look up the coordinates of a supplied 'place'
# first.  If no place is given as an argument, then use the user's preference
# setting if it is available. If the user doesn't have a preference, use the
# default 'Campus'.
#
# Parameters:
# $server Ignored.
# $params A string with either:
#         A latitude and longitude, separated by a space.
#         A 'point of interest' stored in the %locations hash.
#         A Dutch city name.
#         A different nickname which has stored a preference location.
#         or...
#         The empty string. When the nickname calling the wrapped function has
#         a stored prefrence location, use it. Otherwise use the default
#         location 'Campus'.
# $nick Ignored.
# $address Ignored.
# $target Ignored.
# $function A reference to the function being wrapped, currently either 'regen'
#           or 'zon'.
#
# Returns:
# The result of the wrapped function, augmented with some extra information
# like a Google Maps URL.
sub _wrapper
{
	my ($server, $params, $nick, $address, $target, $function) = @_;

	my ($coords, $regen, $maps, $lat, $lon, $check);

	# Any options given? Strip them out for now.
	my $options = '';
	if ($params and $params =~ s/\s*(--\w+)\s*//g)
	{
		$options = $1;
	}

	# TODO: Is using 'defined $users{$nick}{location}' better?
	if (!$params)
	{
		# No parameter, but the IRC nick has a preferred location.
		#
		# Also capitalise the first character of the location which is stored
		# as an all lowercase string.
		unless ($params = ucfirst($users{$nick}{location}))
		{
			# No parameter and no preferred location, so we'll use the default
			# 'Campus'.
			$params = 'Campus';
		}
	}

	# Look up the coordinates of the given place. Return if the place couldn't
	# be found, or if multiple cities are found.
	$coords = place($server, $params, $nick, $address, $target);
	
	if ($check = _checkPlace($server, $coords, $nick, $address, $target))
	{
		# Is it a nickname, and does that nickname have a location set?
		my $channel = $server->channel_find($target);
		if ($channel and $channel->nick_find($params) and
		    $users{$params}{location})
		{
			# $params will keep the nick, so it will be part of the return
			# string and hopefully highlight someone.
			my $loc = ucfirst($users{$params}{location});
			# Valid location should've been checked while saving the
			# preference...
			$coords = place($server, $loc, $nick, $address, $target);
		}
		else
		{
			return $check;
		}
	}

	# Google maps URL.
	($lat, $lon) = split(/ /, $coords);
	$maps = join('', 'http://maps.google.com/maps?z=14&q=loc:',
	                 $lat, '+', $lon);

	return join('', $function->($server, $options . $coords, $nick,
	                            $address, $target),
	                ' ', $params, ': ', $maps);
}

# Store the preferences of a certain IRC nick.
#
# Parameters:
# $server Ignored.
# $params A key/value pair for a specific preference. They key must be a valid
#         preference setting. Example: wstation Den Helder
# $nick The IRC nick that wants to store his or her preference.
# $address Ignored.
# $target Ignored.
#
# Returns:
# A confirmation of the stored preference if everything went well. Returns an
# error message if no key/value pair was given, or if the key was not a valid
# preference setting.
sub set
{
	my ($server, $params, $nick, $address, $target) = @_;

	my ($key, $value);

	if ($params =~ /(\S+)\s+(\S.*)/)
	{
		$key = lc $1;
		$value = $2;
	}
	else
	{
		return 'Heb zowel een optie als een waarde nodig.'
	}
	
	if (exists $settings{$key})
	{
		# If the user/nick wants to store a location, check whether this
		# location is a valid city or a valid point of interest.
		if ($key eq 'location')
		{
			my ($coords, $check);

			$coords = place($server, $value, $nick, $address, $target);

			if ($check = _checkPlace($server, $coords, $nick,
			                         $address, $target))
			{
				return $check;
			}
		}
		elsif ($key eq 'regen')
		{
			unless (lc $value eq 'ascii' or
				    lc $value eq 'utf-8')
			{
				return "De regen-setting verwacht 'ascii' of 'utf-8'.";
			}
		}


		$users{$nick}{$key} = $value;
		store \%users, Irssi::get_irssi_dir . '/scripts/users';
		return join('', $key, ' is nu ', $value, '.');
	}
	else
	{
		return $key . ' is helaas geen setting.';
	}
}

# Show the preferences of an IRC nick, along with the default values for a
# certain setting. Preferences that aren't set will still be shown.
#
# Parameters:
# $server Ignored.
# $params Ignored.
# $nick The IRC nick that wants to look up the preferences he/she stored for
#       certain commands.
# $address Ignored.
# $target Ignored.
#
# Returns:
# A string with the preferences for the IRC nick, separated by a literal \n. If
# the nick doesn't have a preference for a certain setting, '-' will be shown.
# Every setting will also list the default value.
sub prefs
{
	my ($server, $params, $nick, $address, $target) = @_;

	my $message = "";
	my ($key, $value);

	foreach $key (keys %settings)
	{
		$message = join('', $message, $key, ': ');
		$value = '-' unless ($value = ($users{$nick}{$key}));
		$message = join('', $message, $value,
		                ' (Default: ', $settings{$key}, ')\n');
	}

	return $message;
}

# Delete a preference, or all the preferences, of an IRC nick.
#
# Parameters:
# $server Ignored.
# $params The preference to delete, or 'all' to delete every preference.
# $address Ignored.
# $target Ignored.
#
# Returns:
# A confirmation of deleting a single preference or all preferences. A warning
# message if the preference couldn't be deleted because it didn't exist.
sub delete
{
	my ($server, $params, $nick, $address, $target) = @_;

	if (exists $users{$nick}{$params})
	{
		delete $users{$nick}{$params};
		store \%users, Irssi::get_irssi_dir . '/scripts/users';
		return join('', 'Voorkeur voor ', $params, ' gewist.');
	}
	elsif ($params eq 'all')
	{
		delete $users{$nick};
		store \%users, Irssi::get_irssi_dir . '/scripts/users';
		return 'Al je voorkeuren gewist.';
	}
	elsif ($params eq '')
	{
		return join('', 'Je moet wel opgeven wat je wilt wissen, ',
		                Botsma::Common::scheldwoord(), '.');
	}
	else
	{
		return join(' ', 'Kan', $params, 'niet wissen.');
	}
}

# Look up the coordinates for a given place. This can be either a customly
# defined location in the %locations hash, or a Dutch city. It can even be GPS
# coordinates, to provide an easy way to pass everything 'location based' to
# this function.
#
# Parameters:
# $server Ignored.
# $params String with the name of a Dutch city, a location from the
#         %locations hash, or GPS coordinates.
# $address Ignored.
# $target Ignored.
#
# Returns:
# A string with the latitude and longitude of the place, separated by a space.
# If the place wasn't found, the empty string is returned.
# If multiple cities (with the same name) were found, return a string with a
# warning and a list of the cities, province and coordinates. Each city is
# separated with a literal '\n'.
sub place
{
	my ($server, $params, $nick, $address, $target) = @_;

	# Are these GPS coordinates, so we can pass them on immediately?
	if (Botsma::Common::validcoords(@_))
	{
		return $params;
	}

	# First check whether the place is a custom location. If it isn't, look it
	# up in the city database.
	if ($locations{lc $params})
	{
		return join(' ', $locations{lc $params}{lat},
		                 $locations{lc $params}{lon});
	}
	else
	{
		my @cities = split(/\\n/, Botsma::Common::citycoords(@_));

		# No results!
		if (!(scalar @cities))
		{
			return '';
		}
		elsif (scalar @cities == 1)
		{
			# Only get the coordinates.
			if ($cities[0] =~ m/(-?\d\d?\.\d+)\s(-?\d\d?\d?\.\d+)/)
			{
				return join(' ', $1, $2);
			}
			# This means that the string was wrongly formatted.
			else
			{
				return '';
			}
		}
		else
		{
			return join('\n', 'Meerdere steden gevonden. Plak de ' .
			                  'provincie-afkorting erachter om een unieke ' .
			                  'te kiezen:', @cities);
		}
	}
}

# Helper function to validate the result from place().
#
# Returns appropriate messages if the result from place() if no city was found,
# or if multiple cities were found.

# Parameters:
# $server Ignored.
# $params The result from place().
# $nick Ignored.
# $address Ignored.
# $target Ignored.
#
# Returns:
# The string 'Dat gehucht kan niet worden gevonden.' if no city was found. This
# means that the result from place() was the empty string.
# or...
# A list of cities to choose from if multiple cities were found. See the
# documentation at place().
sub _checkPlace
{
	my ($server, $params, $nick, $address, $target) = @_;

	if (!$params)
	{
		# City not found.
		return 'Dat gehucht kan niet worden gevonden.';
	}
	elsif (!Botsma::Common::validcoords(@_))
	{
		# Multiple cities.
		return $params;
	}
	else
	{
		# Normal, valid coordinates.
		return '';
	}
}

sub zon
{
	return _wrapper(@_, \&Botsma::Common::zon);
}

sub regen
{
	my ($server, $params, $nick, $address, $target) = @_;

	if ($users{$nick}{regen} and lc $users{$nick}{regen} eq lc 'ascii')
	{
		# Add ascii option to the parameters.
		$_[1] = join(' ', '--ascii', $_[1]);
	}
	return _wrapper(@_, \&Botsma::Common::regen);
}

# Store the %links hash to disk.
sub storeLinks
{
	store \%links, Irssi::get_irssi_dir . '/scripts/links';
}

# Check the status of what.cd's site, IRC and tracker by utilizing
# whatstatus.info.
#
# Returns:
# The statuses...
sub what
{
	my ($server, $params, $nick, $address, $target) = @_;

	my $url = get 'https://whatstatus.info/api/status' or
		return 'Cannot reach whatstatus.info';


	my ($decoded, $site, $irc, $tracker);

	# Ignore exceptions from JSON.
	eval
	{
		$decoded = decode_json($url);
		$site = $decoded->{site};
		$irc = $decoded->{irc};
		$tracker = $decoded->{tracker};
	};

	return join(' ', '[Whatcd]',
	                 'Site:', _colourStatus($site),
	                 'IRC:', _colourStatus($irc),
	                 'Tracker:', _colourStatus($tracker));
}

sub _colourStatus
{
	my $status = $_[0];

	if ($status)
	{
		return chr(03).'03UP'.chr(03);
	}
	else
	{
		return chr(03).'04DOWN'.chr(03);
	}
}

sub _whatChange
{
	my ($server, $params, $nick, $address, $target) = @_;

	my $url = get 'https://whatstatus.info/api/status' or
		return;

	my ($decoded, @newstatus);

	# Ignore exceptions from JSON.
	eval
	{
		$decoded = decode_json($url);
	};

	my $component;

	# All the values are only undefined at start. So, if one of the values is
	# undefined, this is the first time we got called.
	if (!(defined $whatStatus{site}))
	{
		foreach $component (qw(site irc tracker))
		{
			$whatStatus{$component} = $decoded->{$component};
		}
	}
	else
	{
		my $isChanged = 0;

		foreach $component (qw(site irc tracker))
		{
			# This fails if $decoded->{$component} doesn't exist...
			if ($whatStatus{$component} != $decoded->{$component})
			{
				$isChanged = 1;
				$whatStatus{$component} = $decoded->{$component};
			}
		}

		if ($isChanged)
		{
			my $msg = join(' ', '[Whatcd] Status change!',
	                 'Site:', _colourStatus($decoded->{site}),
	                 'IRC:', _colourStatus($decoded->{irc}),
	                 'Tracker:', _colourStatus($decoded->{tracker}));
			$server = Irssi::server_find_tag('IRCnet');
			$server->command('msg #inter-actief ' . $msg);
		}
	}
}
		
sub source
{
	return "https://github.com/DeltaLeonis/botsma";
}

signal_add("message public", "_parsePublic");
signal_add("message private", "_parsePrivate");

# Every 2 minutes.
timeout_add(120000, 'p2000', undef);
#timeout_add(120000, '_whatChange', undef);
# Every 6 hours.
timeout_add(21600000, 'storeLinks', undef);
