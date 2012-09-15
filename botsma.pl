use strict;
use utf8;
use vars qw($VERSION %IRSSI);

use Irssi qw(signal_add timeout_add);
use Irssi::TextUI;

use LWP::Simple qw(:DEFAULT $ua);

use DateTime::Format::Strptime;

use Botsma::Common;
use Botsma::WStations;

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

if (open(F, '.irssi/scripts/excuses'))
{
	@excuse = <F>;
}
else
{
	print 'Kon de excuse-file niet openen. Ironisch!';
}

# Read users preferences from disk
my %users = %{retrieve('.irssi/scripts/users')};

# Possible user settings, with default values. Note that these default values
# are actually implemented/harcoded in the subroutines, so they're just used
# informatively here.
my %settings =
(
	wstation => 'Twenthe',
	location => 'Enschede',
);

#my %users =
#(
#	akaIDIOT =>
#	{
#		wstation => 'Hoek van Holland',
#		location => 'Den Haag'
#	},
#	DTM =>
#	{
#		wstation => 'De Bilt',
#		location => 'Bussum'
#	},
#	# Zosma =>
#	# {
#	# 	wstation => 'Den Helder',
#	# 	location => 'Lutjebroek'
#	# }
#);

my %locations =
(
	campus =>
	{
		lat => 52.247195,
		lon => 6.848019,
	}
);

# A wrapper for when the commands are given in a private chat, or when 'I'
# (this irssi user) issued the commands myself.
# The order of parameters is different in that case.
sub owncommand
{
	my ($server, $msg, $nick, $address, $target) = @_;
	# Not sure why we used '' for $nick here... try a while *with* $nick.
	####command($server, $msg, '', $address, $nick);

	# Nick also becomes target.
	command($server, $msg, $nick, $address, $nick);
}

# Execute the command given to the 'bot'. Only responds if prefixed by my nick
# plus a colon, like 'Zosma: temp'.
#
# This function also provides a substitute 'command' for people in some
# channels. For example, they can type 's/old/new' to correct their previous
# sentence.
# 
# Parameters:
# $server The server from which the message originated.
# $msg The entire message.
# $nick The nickname that typed the message.
# $address User or server host? Ignored anyway.
# $target The IRC channel or IRC query nickname.
#
sub command
{
	my ($server, $msg, $nick, $address, $target) = @_;

	my
	(
		$reply, $part, $cmd, $cmdref, $params, $mynick, $pattern, $replace,
		$flags, $corrNick, $substWindow, $lines, $original, $substitution
	);

	$mynick = $server->{nick};

	# When the nick is empty, it's probably ourselves.
	#### $nick = $mynick if ($nick eq '');

	if ($msg =~ m/^$mynick:/i)
	{
		# Strip the prefix.
		$msg =~ s/$mynick:\s*//i;
		# Parse the line into the command and parameters.
		($cmd, $params) = split(/\s+/, $msg, 2);

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
	elsif (($target eq "#inter-actief" || $target eq '#testchan') and
	       $msg =~ m#(https?://.*youtube.*/watch\?.*v=[A-Za-z0-9_\-]+|https?://youtu\.be/[A-Za-z0-9_\-]+)#)
	{
		my $match = $1;
		my $url = get 'http://www.youtube.com/oembed?url=' . $match;
		my $decoded = decode_json($url);

		$reply = $decoded->{title};
	}
	elsif (($target eq '#inter-actief' || $target eq "#testchan") and
	       $msg =~ m#(https?://.*vimeo\.com/\d+)#)
	{
		my $match = $1;
		$ua->agent('Botsma');
		my $url = get 'http://vimeo.com/api/oembed.json?url=' . $match;
		my $decoded = decode_json($url);
		$reply = join(': ', $decoded->{title}, $decoded->{description});
		# Description can be quite large... strip to 100 characters or something?
		$reply = join('', substr($reply, 0, 100), '...');
	}

	# Someone is trying to substitute (correct) his previous sentence.
	#
	# With optional last separator (but note that it gives problems with,
	# for example: s/old/newi because that's interpreted as s/old/new/i
	elsif (($target eq "#inter-actief" || $target eq "#testchan") and
		   $msg =~ m/^s([\/|#.:;])(.*?)\1(.*?)\1?([gi]*)$/)
	{
		$pattern = $2;
		$replace = $3;
		$flags = $4;

		#$substWindow = Irssi::window_find_item("#inter-actief");
		$substWindow = Irssi::window_find_item($target);
		my $lines = $substWindow->view()->get_lines();

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
			if ($lines->get_text(0) =~ m/\d\d:\d\d ( \* (\S+)|<[\s\@\+\&](.+)>) (.*\Q$pattern\E.*)$/)
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
			$substitution = substitute($pattern, $replace, $flags, $original);

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
	}

	# Send the reply to the target (channel/nick), if it exists.
	if ($reply)
	{
		foreach $part (split(/\\n/, $reply))
		{
			# Ugly way to sleep half a second
			# select(undef, undef, undef, 0.5);
			$server->command('msg '.$target.' '.$part);
			$server->command('wait 50');
		}
	}
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
sub substitute
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
# $target Target channel, or nick in case of a /query.
#
# Returns:
# Temperature of Twenthe or the supplied weather station or...
# Temperature difference between a users' preferred weather station and Twenthe
# or...
# An error message.
sub temp
{
	my ($server, $params, $nick, $address, $target) = @_;

	# Some user has a location station set. We will automatically determine the
	# nearest weather station, and show the difference with Twenthe (if it's
	# not Twenthe itself...).
	if (!$params and defined $users{$nick}{location})
	{
		# Coordinates of the user's location.
		my $coords;
		# Nearest weather station to the user's location.
		my $userStation;
		# Temperature of the user's weather station, and the temperature of
		# Twenthe.
		my ($userTemp, $twenthe);

		# Replace $params with the user defined setting.
		$params = $users{$nick}{location};

		# Look up the coordinates of the given place. Return if the place couldn't
		# be found, or if multiple cities are found.
		$coords = place($server, $params, $nick, $address, $target);

		my $check;
		if ($check = _checkPlace($server, $coords, $nick, $address, $target))
		{
			return $check;
		}

		$userStation = Botsma::WStations::nearest($coords);
		$twenthe = Botsma::Common::temp($server, '', $nick, $address, $target);

		# Return the default Twenthe temperature, because the nearest weather
		# station turned out to be Twenthe.
		return Botsma::Common::temp(@_) if ($userStation eq 'Twenthe');

		# Otherwise continue and show the difference between the weather
		# station of the user and Twenthe.
		$userTemp = Botsma::Common::temp($server, $userStation, $nick,
		                                 $address, $target);

		# Strip degrees, if not succesful it means some temperature was broken.
		if ($twenthe =~ s/ °C// and $userTemp =~ s/ °C//)
		{

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

			return join('', $userStation, ' (', $userTemp, ' °C) is ',
			                $warmth, ' Twenthe (', $twenthe, ' °C)');
		}
		else
		{
			return 'Er is iets fout... waarschijnlijk is er een meetstation' .
			       ' stuk.';
		}
	}
	else
	{
		# User didn't have a location set, or specified an explicit weather
		# station in $params, so we'll use the default (which is 'Campus').
		return Botsma::Common::temp(@_);
	}
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

# Simple wrapper around Botsma::Common::regen so we can look up the coordinates
# of the supplied place. If no place is given as an argument, then use the
# user's preference setting if it is available. If the user doesn't have a
# preference, use the default 'Campus'.
sub regen
{
	my ($server, $params, $nick, $address, $target) = @_;

	my ($coords, $regen, $maps, $lat, $lon, $check);

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
		return $check;
	}

	# Google maps URL.
	($lat, $lon) = split(/ /, $coords);
	$maps = join('', 'http://maps.google.com/maps?z=14&q=loc:',
	                 $lat, '+', $lon);

	return join('', Botsma::Common::regen($server, $coords, $nick,
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

		$users{$nick}{$key} = $value;
		store \%users, '.irssi/scripts/users';
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
		store \%users, '.irssi/scripts/users';
		return join('', 'Voorkeur voor ', $params, ' gewist.');
	}
	elsif ($params eq 'all')
	{
		delete $users{$nick};
		store \%users, '.irssi/scripts/users';
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

signal_add("message public", "command");
signal_add("message private", "owncommand");
signal_add("message own_public", "owncommand");
signal_add("message own_private", "owncommand");

# Every 2 minutes.
timeout_add(120000, 'p2000', undef);
