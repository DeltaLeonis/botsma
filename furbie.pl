use strict;
use utf8;
use vars qw($VERSION %IRSSI);
use Irssi qw(command_bind signal_add servers timeout_add);
use Irssi::TextUI;
use LWP::Simple;
use Text::ParseWords;
use DateTime;
use DateTime::Format::Strptime;
use POSIX;

#use Data::Dumper;

$VERSION = '0.1';
%IRSSI =
(
	authors => 'Nieko Maatjes, Jorrit Tijben',
	contact => 'jorrit@tijben.net',
	name => 'Furbie Imposter',
	description => 'Cheap alternative for some Furbie functions. Many functions blatantly stolen from http://furbie.net/source/',
	license => 'GPL',
);

my $Strp = new DateTime::Format::Strptime(
	pattern => '%d-%m-%y %T',
);

# The date and time of the last message that was seen by the P2000 announcer.
my $lasttime = '';
my @excuse = ();
my $number;
my %goals = ();

my @rainbox = ("▁", "▂", "▃", "▄", "▅", "▆", "▇", "█");
# my @rainbox = ("1", "2", "3", "4", "5", "6", "7", "8");


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

		# $reply = Irssi::Script::furbie->$cmd($server, $params, $nick,
		# $address, $target); would cause 'Irssi::Script::furbie to be
		# the first argument to $cmd...  The following bypasses that by
		# making use of the can() UNIVERSAL function.
		eval
		{
			$reply = Irssi::Script::furbie->can($cmd)->
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

# Choose one word out of several alternatives. All the alternatives are given
# after the command itself.
#
# Example: kies "Clean the Room" sleep "Play Guitar" run
#
# Parameters: 
# $params The options to choose from.
#
# Returns:
# One of the words from $params.
sub kies
{
	my ($server, $params, $nick, $address, $target) = @_;
	my @words = quotewords('\s+', 0, $params);
	return $words[rand($#words+1)];
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

# Get the current temperature in Frankfurt, Germany.
#
# Returns:
# The temperature in Frankfurkt, Germany in degrees Celsius, as a text string
# with the Celsius symbol added.
# Returns 'Frankfurt is gone' if the temperature couldn't be found.
sub tempPixel
{
	# What a shit-url :-)
	my $url = get 'http://www.dwd.de/bvbw/appmanager/bvbw/dwdwwwDesktop?_nfpb=true&_pageLabel=_dwdwww_wetter_warnungen_deutschlandwetter&T31202958461164878569321gsbDocumentPath=Navigation%2FOeffentlichkeit%2FWetter__Warnungen%2FWetter__Deutschland%2FFormulare%2FStdAw__node.html%3F__nnn%3Dtrue&_state=maximized&_windowLabel=T31202958461164878569321';

	if ($url =~ m/Frankfurt\/M-Flh\.\s+\S+\s+\S+\s+(-?\d+.\d)/i)
	{
		return $1.' °C';
	}
	else
	{
		return 'Frankfurt is gone';
	}
}

# Get the current temperature in Oulu, Finland.
# 
# Returns:
# The temperature in Oulu, Finland in degrees Celsius, as a text string
# with the Celsius symbol added.
# Returns 'Finland is broken' if the temperature couldn't be found.
sub tempLovejoy
{
	my $url = get 'http://ilmatieteenlaitos.fi/saa/Oulu';

	if ($url =~ m/L&auml;mp&ouml;tila<\/span>\s*<span class="parameter-value">(-?\d+,\d)&nbsp;&deg;C<\/span>/i)
	{
		# Can't directly manipulate $1. Why?
		my $temp = $1;
		$temp =~ s/,/\./;
		return $temp.' °C';
	}
	else
	{
		return 'Finland is broken';
	}
}

# Get the current temperature in Church Fenton or Heathrow, United Kingdom.
#
# Parameters:
# $nick If the supplied nick is Square (case insensitive), look up the
#       temperature for Heathrow. Otherwise, look up the temperature for
#       Church Fenton.
#
# Returns:
# The temperature in either Church Fenton or Heathrow, United Kingdom, as a
# text string with the Celsius symbol added.
sub tempEngland
{
	my $nick = $_[0];

	# The Met Office's site is a bit shit... we need the last row from a
	# table of recent measurements. A regex is not really doable because the
	# 'class=' text differs for days and evenings.
	my $url = get 'http://www.metoffice.gov.uk/weather/uk/yh/church_fenton_latest_temp.html';

	if (lc $nick eq 'square')
	{
		# Get the temperature in Heathrow instead.
		$url = get 'http://www.metoffice.gov.uk/weather/uk/se/heathrow_latest_weather.html';
	}

	# /s means .* also matches newlines.
	$url =~ s/^.*<div id="obsTable" class="tableWrapper">\s*<table>//s;
	$url =~ s/<\/table>.*$//s;
	# Strip the first 8 table rows (.* non-greedy!).
	$url =~ s/^\s*(<tr>.*?<\/tr>\s*){8}//s;
	# Strip table row start and first two table data entries.
	$url =~ s/^<tr>\s*(<td.*?<\/td>\s*){2}//s;
	# Get the first line.
	$url = (split/\n/, $url)[0];
	# Fetch temperature between HTML tags.
	$url =~ s/<[^>]*>//g;
	return $url.' °C';
}

sub tempall
{
	my ($server, $params, $nick, $address, $target) = @_;
	my ($enschede, $starbuck, $rincewind, $lovejoy,
		$raverdave, $square, $pixel);

	$enschede = chr(03) . '08' .
		temp(@_) . chr(03) .
		' (' . chr(03) . '08' . 'E' . chr(03) .
		'\'de)';
	$starbuck = chr(03) . '03' .
		temp($server, 'Eelde', $nick, $address, $target) . chr(03) .
		' (' . chr(03) . '03' . 'S' . chr(03) .
		'tarbuck)';
	$rincewind = chr(03) . '13' . 
		temp($server, 'Schiphol', $nick, $address, $target) . chr(03) .
		' (' . chr(03) . '13' . 'R' . chr(03) .
		'incewind)';
	$lovejoy = chr(03) . '12' .
		tempLovejoy() . chr(03) .
		' (' . chr(03) . '12' . 'L' . chr(03) .
		'ovejoy)';
	$raverdave = chr(03) . '05' .
		tempEngland() . chr(03) .
		' (' . chr(03) . '05' . 'R' . chr(03) .
		'averDave)';
	$square = chr(03) . '04' .
		tempEngland('Square') . chr(03) .
		' (' . chr(03) . '04' . 'S' . chr(03) .
		'quare)';
	$pixel = chr(03) . '06' .
		tempPixel() . chr(03) .
		' (' . chr(03) . '06' . 'P' . chr(03) .
		'ixel)';

	# From http://perldoc.perl.org/functions/sort.html
	my @temps = ($enschede, $starbuck, $rincewind, $lovejoy,
				 $raverdave, $square, $pixel);

	my @nums = ();

	for (@temps)
	{
		push @nums, ( /\d\d(-?\d+\.\d)/ ? $1 : undef );
	}

	my @sorted = @temps[ sort {
		$nums[$b] <=> $nums[$a]
		} 0..$#temps
	];

	return join(' | ', @sorted);
}

sub temp
{
	my ($server, $params, $nick, $address, $target) = @_;
	my ($url, $city, @params);

	#print 'Target = '.$target;
	#print 'Nick = '.$nick;

	# UGLY FIX ETC PANIC BBQ!
	if ((lc $nick eq 'dtm') or (lc $target eq 'dtm'))
	{
		return tempdtm();
	}
	elsif ((lc $nick eq 'akaidiot') or (lc $target eq 'akaidiot'))
	{
		return tempaka();
	}

	#@params = split(/\s+/, $params);

	$city = $params;
	if (!$city)
	{
		$city = 'Twenthe';
	}

	my $url = get 'http://www.knmi.nl/actueel/index.html';
	if ($url =~ m/<td>$city<\/td>\s*<td>.*<\/td>\s*<td align=right>(-?\d*.\d)/i)
	{
		return $1.' °C';
	}
	else
	{
		return sprintf('%s %s, %s, anders zoek je eerst even een meetstation op http://www.knmi.nl/actueel/',
					   aanhef(),
					   $nick,
					   scheldwoord());

		return 'Plaatsnaam niet gevonden... waarschijnlijk heeft akaIDIOT het gebombardeerd.';
	}
}

sub tempStockholm
{
	my $url = get 'http://www.smhi.se/en/Weather/Sweden-weather/Observations';
	if ($url =~ m/Stockholm<\/a><\/td><td headers="tV2" align="center" valign="middle">(-?\d*,\d)<\/td>/i)
	{
		my $temp = $1;
		$temp =~ s/,/\./;
		return $temp.' °C';
	}
	else
	{
		return 'Stockholm is broken';
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

sub aanhef
{
	my @aanhef = ('Zeg', 'Hey', 'Geachte', 'Tering', 'Hallo', 'Dag');

	return $aanhef[rand(scalar(@aanhef))];
}

sub scheldwoord
{
	my @scheldwoord =
	(
		'aarsklodder', 'asbestmuis',
		'baggerbeer', 'bamikanariewenkbrauw',
		'chromatiet', 'deegsliert',
		'dromedarisruftverzamelaar', 'ectoplastisch bijprodukt',
		'floskop', 'gatgarnaal',
		'geblondeerde strontbosaap', 'hertensnikkel',
		'hutkoffer op wielen', 'ingeblikte pinguinscheet',
		'ini-mini-scheefgepoepte-pornokabouter', 'kontkorstkrabber',
		'kutsapslurper', 'lesbische vingerplant',
		'lummeltol', 'muppetlolly',
		'netwerkfout', 'neukstengel',
		'onderontwikkelde zeekomkommer', 'polderkoe',
		'quasimodo', 'reetzweetscheet',
		'rimboekikker', 'smegmasnuiver',
		'strontholverklontering', 'trippeleend',
		'uitgekotste kamelenkut', 'veeverkrachter',
		'wortelpotige', 'xylofoonneuker',
		'yoyolul', 'zeekomkommer',
		'kale dwergplaneet', 'drietrapsdebiel',
		'darmwandabces', 'braakemmer',
		'opgegraven veenlijk', 'humorloos pak vla',
		'prutsmuts', 'verrekte koekwaus',
		'puistenplukker', 'droeftoeter',
		'verlepte dakduif', 'stuk kreukelfriet',
		'hardgekookt heksensnotje', 'kansloze kokosmakroon'
	);

	return $scheldwoord[rand(scalar(@scheldwoord))];
}

sub goals
{
	my $url = get 'http://vi.globalsportsmedia.com/vi.html';
	my %live_teams = ();
	my ($key, $value, $result, $server, $server2, $part);

	my $live = '<td class="score_time_live">';

	while ($url =~ m#<td class="team_a">([^\n]*)</td>\s*$live.*?(\d*) - (\d*).*?</td>.*?<td class="team_b">(.*?)</td>#gis)
	{
		if (defined $goals{$1})
		{
			if ($2 > $goals{$1})
			{
				$result = $result.sprintf("!!! %s SCOORT !!! ======<() ♪ ♫ ♪ ♫ ♪ ♫", $1).'\n';
			}
		}

		if (defined $goals{$4})
		{
			if ($3 > $goals{$4})
			{
				$result = $result.sprintf("!!! %s SCOORT !!! ======<() ♪ ♫ ♪ ♫ ♪ ♫", $4).'\n';
			}
		}

		$goals{$1} = $2;
		$goals{$4} = $3;

		$live_teams{$1} = '1';
		$live_teams{$4} = '1';
		#$result = $result.sprintf("[%s] %s - %s [%s]", $2, $1, $4, $3).'\n';
	}

	while (($key, $value) = each %goals)
	{
		if (!(exists $live_teams{$key}))
		{
			delete $goals{$key};
			print "Deleting $key from the goals hash".'\n';
		}
	}

	$server = Irssi::server_find_tag('Blitzed');
	$server2 = Irssi::server_find_tag('IRCnet');
	
	foreach $part (split(/\\n/, $result))
	{
		$server->command('msg #bilge '.$part);
		$server2->command('msg #inter-actief '.$part);
	}
}

sub stand
{
	my $url = get 'http://vi.globalsportsmedia.com/vi.html';
	#my $url = get 'http://vi.globalsportsmedia.com/view.php?sport=soccer&action=Results.View&date=2010-06-24';
	my $result = '';

	my $live = '<td class="score_time_live">';
	my $upcoming = '<td class="score_time kickoff-time">';

	while ($url =~ m#<td class="team_a">([^\n]*)</td>\s*$live.*?(\d*) - (\d*).*?</td>.*?<td class="team_b">(.*?)</td>#gis)
	{
		$result = $result.sprintf("[%s] %s - %s [%s]", $2, $1, $4, $3).'\n';
	}

	if ($result eq '')
	{
		$result = 'Upcoming matches:\n';

		while ($url =~ m#<td class="team_a">([^\n]*)</td>\n*\s*$upcoming.*?(\d\d:\d\d).*?</td>.*?<td class="team_b">(.*?)</td>#gis)
		{
			$result = $result.sprintf("%s - %s om %s", $1, $3, $2).', ';
		}
		$result =~ s/, $//;
	}

	return $result;
}

sub janee
{
	return ((rand) < 0.5) ? 'Ja.' : 'Nee.';
}

sub ali
{
	my ($server, $params, $nick, $address, $target) = @_;
	my ($reply, $cmd);
	($cmd, $params) = split(/\s+/, $params, 2);
	eval
	{
		$reply = Irssi::Script::furbie->can($cmd)->($server, $params, $nick, $address, $target);
		$reply =~ s/\b(een|'n|de)\b\s*//ig;
		$reply =~ s/\b(d)eze\b/$1it/gi;
		$reply =~ s/\bIk\b/Ikke/g; $reply =~ s/\bik\b/ikke/g;
		$reply =~ s/\bhet\b/de/g; $reply =~ s/\bHet\b/De/g;

		$reply =~ s/(s)([^aeiou]|$)/$1j$2/ig;
		$reply =~ s/(z)/$1j/ig;
		$reply =~ s/([^eu]|^)(i)(?!([je]|kke))/$1$2e$3/ig;
		$reply =~ s/[eu]i/ai/g; $reply =~ s/[EU]i/Ai/ig;
		$reply =~ s/uu|eu|u/oe/g; $reply =~ s/Uu|Eu|U/Oe/ig;
		$reply =~ s/(aa)([^aeiou])/$1h$2/g;
		$reply =~ s/(oo)([^aeiou])/$1h$2/g;
	};
	if ($@)
	{
	}

	return $reply;
}

sub citycoords
{
	my ($server, $params, $nick, $address, $target) = @_;
	my $line;
	my $full_name_ro;
	my @splitline;

	print($params);

	if ($params eq "")
	{
		return "";
	}

	open(F, '.irssi/scripts/nl.txt')
		or die("Couldn't open nl.txt");

	while($line = <F>)
	{
		if ($line =~ m/\Q$params\E/i)
		{
			@splitline = split("\t", $line);

			print($splitline[23]);
			
			# Field 24 is FULL_NAME_RO
			if ((lc $params) eq (lc $splitline[23]))
			{
				return join(" ", $splitline[3], $splitline[4]);
			}
		}
	}

	return 'Dat gehucht kan niet worden gevonden';

}

sub bofh
{
	open(F, '.irssi/scripts/excuses') ||
		return 'Kon de excuse-file niet openen. Ironisch!';
	#
	## (c) 1994-2000 Jeff Ballard.
	##
	# http://pages.cs.wisc.edu/~ballard/bofh/
	
	# No need to call srand anymore.
	# srand(time);

	# If the @excuse array isn't filled yet, read the lines from the excuses file
	# and put them in the @excuse array.
	# Might be bad if the file is really large and won't fit into memory.


	# EY! DIT KAN GEWOON IN 1 KEER! DOE EENS AANPASSEN WAUS.
	if (!scalar(@excuse))
	{
		$number = 0;
		while($excuse[$number] = <F>)
		{
			$number++;
		}
	}

	return $excuse[(rand(1000) * $$) % ($number + 1)];
}

sub smoes
{
	my @wat = ("Ik kan nu niet langer blijven"
			  ,"Ik kan nu niet komen"
			  ,"Het komt niet zo goed uit als jullie nu koffie willen drinken"
			  ,"Het bier is nu al wel koud maar toch kan ik niet blijven"
			  ,"Ik kan niet blijven eten"
			  ,"Jullie feestje zal best gezellig zijn maar ik moet weg"
			  ,"Ik kon vanochtend weer niet uitslapen"
			  ,"Ik moet nu echt naar bed"
			  ,"Ik zou graag willen blijven maar ik kan niet"
			  ,"Het wordt geen latertje voor mij vanavond"
			  ,"Nurden is niet aan mij besteed vandaag");
	
	my @waarom = ("mijn schoonmoeder bij ons is ingetrokken"
				 ,"onze jongste zijn amandelen geknipt moeten worden"
				 ,"de kleine zijn pianoles niet kan missen"
				 ,"de caravan nog schoongemaakt moet worden"
				 ,"er nog een stapel was ligt die gestreken moet worden"
				 ,"we morgen naar de zwager van mijn schoonmoeder moeten"
				 ,"de baby altijd al om 5 uur wakker wordt"
				 ,"de nicht van de broer van m'n zwager bevallen is"
				 ,"sesamstraat over 30 minuten begint"
				 ,"het eten anders koud wordt"
				 ,"ik mijn bonsai-knipkruk nog moet schilderen"
				 ,"dat niet mag van mijn vriendin"
				 ,"het gras nog gemaaid moet worden"
				 ,"er voetbal op TV is"
				 ,"het vuilnis nog voorgezet moet worden"
				 ,"er morgen oud papier ingezameld wordt"
				 ,"het jaarlijks familieuitstapje volgende week is"
				 ,"mijn goudvis in brand staat"
				 ,"het morgen de bowlingavond van mijn parkiet is"
				 ,"ik de hond nog in het park moet zoeken"
				 ,"morgen de jaarlijkse hinkelwedstrijd in het dorp is"
				 ,"ik mijn steenpuist nog uit moet knijpen"
				 ,"mijn psychiater mij daar nog niet toe in staat acht"
				 ,"ik anders de weg niet meer terug vind");
   
	return sprintf('%s omdat %s.', $wat[rand(scalar(@wat))], $waarom[rand(scalar(@waarom))]);
}

sub metar
{
	my ($server, $params, $nick, $address, $target) = @_;
	
	my $iaco = $params;
	# Strip special chars
	$iaco =~ s/[^a-zA-Z]*//g;

	my $url = get 'http://weather.noaa.gov/mgetmetar.php?cccc='.$iaco;

	if ($url =~ m/($iaco \d\d\d\d\d\dZ.*)/i)
	{
		return $1;
	}
	else
	{
		return 'No METAR for '.$iaco;
	}
}

sub regen
{
	my ($server, $params, $nick, $address, $target) = @_;

	if ($params eq "")
	{
		$params = 'Enschede';
	}

	my $coords = citycoords($server, $params, $nick, $address, $target);

	if ($coords eq 'Dat gehucht kan niet worden gevonden')
	{
		return $coords;
	}

	my ($lat, $lon) = split(" ", $coords);

	my $url = get join('', 'http://gps.buienradar.nl/getrr.php?', 'lat=', $lat,
		               '&lon=', $lon)
		or print("Buienradar fail");

	my $count = 0;
	my $prediction = "";
	my ($rain, $time, $mm, $bucket);

	my @lines = split(/\n/, $url);
	foreach my $line (@lines)
	{
		if ($line =~ m/(\d\d\d)\|(\d\d:\d\d)/)
		{
			# Range is 000-255
			$rain = $1;
			$time = $2;

			if ($count == 0)
			{
				$prediction = $time . " |";
			}
			elsif ($count % 6 == 0)
			{
				$prediction .= "|";
			}

			# The rain intensity takes values from 000 to 255. The rain in
			# millimeters per hour is calculated with the formula
			# 10 ^ ((waarde - 109) / 32).
			#
			# The range this formula gives, 0-36517, is not really useful, as
			# the rain intensity will rarely be more than 30 mm/h. Still, even
			# that is quite much: experience showed 6 mm/h is a good maximum.
			#
			# What we'll do is: calculate the rain intensity using the above
			# formula, then split the 6 mm up in 8 buckets of 0.75 mm each.
			# Everything more than 6 mm/h will get a red '!'
			if ($rain == 0)
			{
				$prediction .= ' ';
			}
			else
			{
				$mm = 10 ** (($rain - 109) / 32);

				if ($mm > 6)
				{
					$prediction .= join('', chr(03), '04!', chr(03));
				}
				else
				{
					$bucket = floor(($mm * 8) / 6);
					$prediction .= $rainbox[$bucket];
				}
			}

			$count++;
		}
	}

	return join('', $prediction, ' (', $params, ' ', $lat, ' ', $lon, ')');
}

sub clock
{
	my ($dt, $result);

	$dt = DateTime->now()->set_time_zone('Europe/Helsinki');
	$result = 'Finland: ' . $dt->strftime('%R');
	$dt->set_time_zone('Europe/Amsterdam');
	$result .= ', Dtuchland: ' . $dt->strftime('%R');
	$dt ->set_time_zone('Europe/London');
	$result .= ', England: ' . $dt->strftime('%R');
	$dt->set_time_zone('America/Los_Angeles');
	$result .= ', Sandpants: ' . $dt->strftime('%R');

	return $result;
}


signal_add("message public", "command");
signal_add("message private", "owncommand");
signal_add("message own_public", "owncommand");
signal_add("message own_private", "owncommand");

# 10 minutes
# timeout_add(600000, 'p2000', undef);
# 2 minutes
#timeout_add(120000, 'p2000', undef);
# 2 minutes
#timeout_add(120000, 'goals', undef);
