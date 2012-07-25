use strict;
use utf8;
use vars qw($VERSION %IRSSI);

use Irssi qw(signal_add timeout_add);

use LWP::Simple;

use DateTime;

use Botsma::Common;

use warnings;

$VERSION = '0.1';
%IRSSI =
(
	authors => 'Jorrit Tijben',
	contact => 'jorrit@tijben.net',
	name => 'Zosma',
	description => 'Some quick and dirty functions that can be invoked ' .
	               'from IRC.',
	license => 'GPL',
);

my %goals = ();

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

sub command
{
	my ($server, $msg, $nick, $address, $target) = @_;

	my ($reply, $part, $cmd, $cmdref, $params, $mynick);

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


sub tempall
{
	my ($server, $params, $nick, $address, $target) = @_;
	my ($enschede, $starbuck, $rincewind, $lovejoy,
		$raverdave, $square, $pixel);

	$enschede = chr(03) . '08' .
		Botsma::Common::temp(@_) . chr(03) .
		' (' . chr(03) . '08' . 'E' . chr(03) .
		'\'de)';
	$starbuck = chr(03) . '03' .
		Botsma::Common::temp($server, 'Eelde', $nick, $address, $target) .
		chr(03) .  ' (' . chr(03) . '03' . 'S' . chr(03) .  'tarbuck)';
	$rincewind = chr(03) . '13' . 
		Botsma::Common::temp($server, 'Schiphol', $nick, $address, $target) .
		chr(03) .  ' (' . chr(03) . '13' . 'R' . chr(03) .  'incewind)';
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


signal_add("message public", "command");
signal_add("message private", "owncommand");
signal_add("message own_public", "owncommand");
signal_add("message own_private", "owncommand");
