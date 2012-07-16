package Botsma::Common;

use strict;
use utf8;

use LWP::Simple;
use Text::ParseWords;

# Needed for floor().
use POSIX;

# All subroutines have a common set of parameters. Often, things like $server
# or $address are ignored, but because the calls to the subroutines will be
# automatically made from IRC we use the same set of parameters in every
# subroutine.

# Retrieve the temperature of/from a KNMI weather station.
#
# Parameters:
# $server Ignored.
# $params The name of the weather station which can be found at
#         http://www.knmi.nl/actueel/
# $nick The nickname that called this command.
# $address Ignored.
# $target Also the nickname that called this command?
sub temp
{
	my ($server, $params, $nick, $address, $target) = @_;
	my ($url, $city, @params);

	print 'Target = '.$target;
	print 'Nick = '.$nick;

	# UGLY FIX ETC PANIC BBQ!
	#if ((lc $nick eq 'dtm') or (lc $target eq 'dtm'))
	#{
	#	return tempdtm();
	#}
	#elsif ((lc $nick eq 'akaidiot') or (lc $target eq 'akaidiot'))
	#{
	#	return tempaka();
	#}

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
		return sprintf('%s %s, %s, anders zoek je eerst even een meetstation' .
			           'op http://www.knmi.nl/actueel/',
					   aanhef(), $nick, scheldwoord());
	}
}

# Report the scores of today's football (soccer!) matches.
#
# Returns:
# A multiline string with either a string with the scores of currently live
# matches, separated by a literal '\n'.  Or, if no matches are currently live,
# return a string with the upcoming matches.
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

# Get a salutation.
#
# Returns:
# A random salutation, for example 'Hey'.
sub aanhef
{
	my @aanhef = ('Zeg', 'Hey', 'Geachte', 'Tering', 'Hallo', 'Dag');

	return $aanhef[rand(scalar(@aanhef))];
}

# Return an insult.
#
# Returns:
# A random insult.
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

# Coin tosser (say yes or no)
#
# Returns:
# Randomly either 'Ja.' or 'Nee.'
sub janee
{
	return ((rand) < 0.5) ? 'Ja.' : 'Nee.';
}

# Like some other subroutines, taken directly from Furbie (http://furbie.net/).
#
# Laat Furbie Turks/Marokkaans-Nederlands praten.
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

# Get a METAR for an airport with a certain ICAO code.
#
# Parameters:
# $server Ignored.
# $params The ICAO code of the aiport you want to get the METAR from.
# $nick Ignored.
# $address Ignored.
# $target Ignored.
#
# Returns:
# A string with the METAR report, or a 'No METAR for' plus the $params if the
# METAR couldn't be found.
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

# Choose one word out of several alternatives. All the alternatives are given
# after the command itself.
#
# Example: kies "Clean the Room" sleep "Play Guitar" run
#
# Parameters: 
# $server Ignored.
# $params The options to choose from.
# $nick Ignored.
# $address Ignored.
# $target Ignored.
#
# Returns:
# One of the words from $params.
sub kies
{
	my ($server, $params, $nick, $address, $target) = @_;
	my @words = quotewords('\s+', 0, $params);
	return $words[rand($#words+1)];
}

# Get the GPS coordinates of a city in The Netherlands.
#
# Parameters:
# $server Ignored.
# $params The name of the city.
# $nick Ignored.
# $address Ignored.
# $target Ignored.
# 
# Returns:
# Latitude and longtitude, separated by a space.
# Empty string if no city was specified.
# String with an error message if the database file couldn't be opened.
sub citycoords
{
	my ($server, $params, $nick, $address, $target) = @_;

	my ($line, $full_name_ro, @splitline);

	if ($params eq '')
	{
		return '';
	}

	open(F, '.irssi/scripts/nl.txt') or
		return "Couldn't open the coordinate database";

	while ($line = <F>)
	{
		# Line was found but it could be a municipality instead of the city.
		if ($line =~ m/\Q$params\E/i)
		{
			@splitline = split("\t", $line);

			# There is a problem for places with the same name, for example
			# Hengelo (OV) and Hengelo (GLD). Right now this subroutine just
			# finds the first match, but a neater solution would be nice.

			# Field 24 is FULL_NAME_RO.
			# Field 4 and 5 are the latitude and longitude.
			if ((lc $params) eq (lc $splitline[23]))
			{
				return join(" ", $splitline[3], $splitline[4]);
			}
		}
	}

	return 'Dat gehucht kan niet worden gevonden';
}

# Get an 'ASCII art' graph of the expected rain in a certain Dutch city.
#
# Actually, 8 different UTF-8 block symbols are used to make up the graph.
# Every block represents 0.75 mm/h rain. If more than 6 mm/h is expected for a
# certain period, a red exclamation mark will be displayed. Every UTF-8 block
# symbol has a time span of 5 minutes; a vertical bar is set at every 30
# minutes.
#
# Parameters:
# $params The city for which a prediction must be made. There is one hardcoded
#         location 'Campus' that wouldn't otherwise be in the city database.
#
# Returns:
# UTF-8 'graph' of the rain prediction, or:
# An appropriate message if the city couldn't be found.
# A message that the website containing the predictions had connection
# failures.
sub regen
{

	my ($server, $params, $nick, $address, $target) = @_;
	my @rainbox = ("▁", "▂", "▃", "▄", "▅", "▆", "▇", "█");

	if ($params eq '')
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

# Return an excuse.
#
# Returns:
# A random excuse/smoes.
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
   
	return sprintf('%s omdat %s.', $wat[rand(scalar(@wat))],
		           $waarom[rand(scalar(@waarom))]);
}

1;
