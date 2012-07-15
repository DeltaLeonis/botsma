use strict;
use utf8;
use vars qw($VERSION %IRSSI);

use Irssi qw(signal_add timeout_add);
use Irssi::TextUI;

use LWP::Simple;
use Text::ParseWords;

use DateTime;
use DateTime::Format::Strptime;

# Needed for floor().
use POSIX;

use Botsma::Common;

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
print("Reading the BOFH excuse file");
my @excuse;

if (open(F, '.irssi/scripts/excuses'))
{
	@excuse = <F>;
}
else
{
	print 'Kon de excuse-file niet openen. Ironisch!';
}

# A wrapper for when the commands are given in a private chat, or when 'I'
# (this irssi user) issued the commands myself.
# The order of parameters is different in that case.
sub owncommand
{
	my ($server, $msg, $nick, $address, $target) = @_;
	command($server, $msg, '', $address, $nick);
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
		$reply, $part, $cmd, $params, $mynick, $pattern, $replace, $flags,
		$corrNick, $substWindow, $lines, $original, $substitution
	);

	$mynick = $server->{nick};

	# When the nick is empty, it's probably ourselves.
	$nick = $mynick if ($nick eq '');

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
			$reply = Irssi::Script::botsma->can($cmd)->
				($server, $params, $nick, $address, $target);
			# Ehm... &($cmd) works too?
		};
		if ($@)
		{
			#warn $@;
			# Could be other errors though...
			# $server->command('msg '.$target.' Dat commando moet Dutchy nog implementeren.');
		}
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
				print('corrNick = ', $corrNick, ' , orginal = ', $original);
				last;
			}

			$lines = $lines->prev();
		}

		# If $lines is not defined now, it means the pattern didn't match.
		if (defined $lines)
		{
			print("Matching line is ", $lines->get_text(0));
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

	# Send the reply to the target (channel/nick).
	foreach $part (split(/\\n/, $reply))
	{
		# Ugly way to sleep half a second
		# select(undef, undef, undef, 0.5);
		$server->command('msg '.$target.' '.$part);
		$server->command('wait 50');
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
		$url, $msg, $valid, $key, $value, $brandweer, $ambulance, $politie, $server,
		$part, $dt
	);

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

	my $url = get 'http://www.p2000-online.net/p2000.php?Brandweer=1&Ambulance=1&Politie=1&Twente=1&AutoRefresh=uit';

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

	# Add mIRC-colours: Brandweer in red, Politie in blue, Ambulance in green.
	$brandweer = chr(03).'04Brandweer'.chr(03);
	$politie = chr(03).'12Politie'.chr(03);
	$ambulance = chr(03).'09Ambulance'.chr(03);

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

sub tempdtm
{
	my ($server, $params, $nick, $address, $target) = @_;
	#my $stockholm = tempStockholm();
	# Not really stockholm anymore ;-)
	my $stockholm = temp($server, 'De Bilt', $nick, $address, $target);
	my $enschede = temp('','','','','');

	# Strip degrees, if not succesful it means some temperature was broken.
	if ($enschede =~ s/ °C// and $stockholm =~ s/ °C//)
	{
		if ($stockholm < $enschede) 
		{
			return 'De Bilt ('.$stockholm.' °C) is '.
			       sprintf('%.1f', $enschede - $stockholm).
				   ' graden kouder dan Twenthe ('.$enschede.' °C).';
		}
		else
		{
			return 'De Bilt ('.$stockholm.' °C) is '.
			       sprintf('%.1f', $stockholm - $enschede).
				   ' graden warmer dan Twenthe ('.$enschede.' °C).';
		}
	}
}

sub tempaka
{
	my ($server, $params, $nick, $address, $target) = @_;
	my $hvh = temp($server, 'Hoek van Holland', $nick, $address, $target);
	my $enschede = temp('','','','','');

	# Strip degrees, if not succesful it means some temperature was broken.
	if ($enschede =~ s/ °C// and $hvh =~ s/ °C//)
	{
		if ($hvh < $enschede) 
		{
			return 'Hoek van Holland ('.$hvh.' °C) is '.
			       sprintf('%.1f', $enschede - $hvh).
				   ' graden kouder dan Twenthe ('.$enschede.' °C).';
		}
		else
		{
			return 'Hoek van Holland ('.$hvh.' °C) is '.
			       sprintf('%.1f', $hvh - $enschede).
				   ' graden warmer dan Twenthe ('.$enschede.' °C).';
		}
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

signal_add("message public", "command");
signal_add("message private", "owncommand");
signal_add("message own_public", "owncommand");
signal_add("message own_private", "owncommand");

# Every 2 minutes.
timeout_add(120000, 'p2000', undef);
