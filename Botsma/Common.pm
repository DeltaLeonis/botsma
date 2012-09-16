package Botsma::Common;

use strict;
use utf8;

use LWP::Simple;
use Text::ParseWords;
use Astro::Sunrise;

# Needed for floor().
use POSIX;

use Switch;

my %province =
(
	"01" => "DR",
	"16" => "FL",
	"02" => "FR",
	"03" => "GD",
	"04" => "GR",
	"05" => "LB",
	"06" => "NB",
	"07" => "NH",
	"15" => "OV",
	"09" => "UT",
	"10" => "ZL",
	"11" => "ZH"
);

my %revProvince =
(
	DR => "01",
	FL => "16",
	FR => "02",
	GD => "03",
	GR => "04",
	LB => "05",
	NB => "06",
	NH => "07",
	OV => "15",
	UT => "09",
	ZL => "10",
	ZH => "11"
);

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
#         If no weather station name is supplied, use 'Twenthe' as a default.
# $nick The nickname that called this command.
# $address Ignored.
# $target Also the nickname that called this command?
#
# Returns:
# The temperature with ' °C' attached, or an insult if the weather station
# doesn't exist. 
sub temp
{
	my ($server, $params, $nick, $address, $target) = @_;
	my ($url, $city, @params);

	$city = $params;
	if (!$city)
	{
		$city = 'Twenthe';
	}

	my $url = get 'http://www.knmi.nl/actueel/index.html';
	if ($url =~ m/<td>$city<\/td>\s*<td>.*<\/td>\s*<td align=right>(-?\d*\.\d)?/i)
	{
		if ($1)
		{
			return $1.' °C';
		}
		else
		{
			return 'De temperatuur van dit meetstation is (tijdelijk) ' .
			       'niet beschikbaar.';
		}
	}
	else
	{
		# Would be nicer if we make a distinction between a non-existing
		# weather station and a missing temperature value.
		return sprintf('%s %s, %s, anders zoek je eerst even een ' .
		               'meetstation op http://www.knmi.nl/actueel/',
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
# Because there are cases where different places share the same name, this
# function returns the city name, province abbreviation and GPS coordinates. If
# multiple cities are found, separate them with a literal '\n' (not newline,
# but a backslash and 'n').
#
# The city name and province abbreviation are given to enable a calling
# function to supply a unique city name.
#
# For example, if the caller has 'Rijswijk' as its argument, this function will
# return:
#
# Rijswijk GD 51.958553 5.357228\nRijswijk NB 51.799972 5.022524\nRijswijk ZH 52.025498 4.310793
#
# Calling this function again with 'Rijswijk GD' only returns
#
# Rijswijk GD 51.958553 5.357228
#
# For places that are unique, calling them without a province abbreviation is
# sufficient.
# 
# Parameters:
# $server Ignored.
# $params A string with the name of the city.
# $nick Ignored.
# $address Ignored.
# $target Ignored.
# 
# Returns:
#
# A string with the city name, province abbreviation and GPS coordinates,
# separated by spaces. Multiple results are separated by a literal '\n'.
# 
# Note that a city can, of course, also have spaces in the name.
#
# The empty string is returned if no city was specified, or if the city could
# not be found.
# Returns an error message if the database file couldn't be opened.
sub citycoords
{
	my ($server, $params, $nick, $address, $target) = @_;

	my ($line, $full_name_ro, @splitline, $city, $cities, $provAbbr);

	if ($params eq '')
	{
		return '';
	}

	open(F, '.irssi/scripts/nl.txt') or
		return "Couldn't open the coordinate database.";
	
	$params =~ s/ (\w\w)$//;
	$provAbbr = $revProvince{uc $1};

	$cities = '';

	while ($line = <F>)
	{
		# Line was found but it could be a municipality instead of the city.
		if ($line =~ m/\Q$params\E/i)
		{
			@splitline = split(/\t/, $line);

			# Field 24 is FULL_NAME_RO.
			# Field 4 and 5 are the latitude and longitude.
			# Field 14 is ADM1 (province in this case).
			if ((lc $params) eq (lc $splitline[23]))
			{
				$city = join(' ', $splitline[23], $province{$splitline[13]},
				                  $splitline[3], $splitline[4]);
				# Caller specified a province, return only one item.
				if ($provAbbr and $provAbbr eq $splitline[13])
				{
					return $city;
				}
				else
				{
					$cities = $cities . $city . '\n';
				}
			}
		}
	}

	return $cities;
}

# Get an 'ASCII art' graph of the expected rain in a certain Dutch city.
#
# Actually, 8 different UTF-8 block symbols are used to make up the graph.
# Every block represents 0.75 mm/h rain. If more than 6 mm/h is expected for a
# certain period, colours will be added in the ranges 6-7 mm/h, 7-8 mm/h, 8-9
# mm/h, 9-10 mm/h. For more than 10 mm/h, the colour will be red.
#
# Every UTF-8 block
# symbol has a time span of 5 minutes; a vertical bar is set at every 30
# minutes.
#
# Parameters:
# $server Ignored.
# $params GPS coördinates like '52.219515 6.891235'.
# $nick Ignored.
# $address Ignored.
# $target Ignored.
#
# Returns:
# UTF-8 'graph' of the rain prediction, or
# An appropriate message if invalid GPS coordinates are supplied, or
# A message that the website containing the predictions had connection
# failures.
sub regen
{

	my ($server, $params, $nick, $address, $target) = @_;
	my @rainbox = ("▁", "▂", "▃", "▄", "▅", "▆", "▇", "█");

	my ($lat, $lon, $url);

	# Check whether a latitude and longitude were given. Must have at least
	# a dot and one decimal after the dot.
	if ($params =~ m/(-?\d\d?\.\d+)\s(-?\d\d?\d?\.\d+)/)
	{
		$lat = $1;
		$lon = $2;
	}
	else
	{
		return 'Invalid GPS coordinates.';
	}

	$url = get join('', 'http://gps.buienradar.nl/getrr.php?', 'lat=', $lat,
	                    '&lon=', $lon)
		or return "Buienradar lijkt stuk te zijn";

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
			if ($rain == 0)
			{
				$prediction .= ' ';
			}
			else
			{
				$mm = 10 ** (($rain - 109) / 32);

				# Colour 6-7 mm with blue, 7-8 mm with green, 8-9 mm with
				# yellow, 9-10 mm with orange, and 10+ mm with red. Otherwise,
				# use the appriopriate uncoloured characters from $rainbox.
				switch($mm)
				{
					case { $_[0] > 6 and $_[0] <= 7 }
					{
						$prediction .=
							join('', chr(03), '11', $rainbox[7], chr(03));
					}
					case { $_[0] > 7 and $_[0] <= 8 }
					{
						$prediction .=
							join('', chr(03), '09', $rainbox[7], chr(03));
					}
					case { $_[0] > 8 and $_[0] <= 9 }
					{
						$prediction .=
							join('', chr(03), '08', $rainbox[7], chr(03));
					}
					case { $_[0] > 9 and $_[0] <= 10 }
					{
						$prediction .=
							join('', chr(03), '07', $rainbox[7], chr(03));
					}
					case { $_[0] > 10 }
					{
						$prediction .=
							join('', chr(03), '04', $rainbox[7], chr(03));
					}
					else
					{
						$bucket = floor(($mm * 8) / 6);
						$prediction .= $rainbox[$bucket];
					}
				}
			}

			$count++;
		}
	}

	return $prediction;
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

# Get the sunset and sunrise for a given longitude and latitude.
#
# Parameters:
# $params The longitude and latitude.
#
# Returns:
# A string with the sunrise and sunset for today at the given longitude and
# latitude, in HH:MM format.
sub zon
{
	my ($server, $params, $nick, $address, $target) = @_;

	# TODO: FIX THIS NEATLY ETC. RAGE BOO
	# WARNING TODO: THIS IS CODE REPLICATION
	# WOOOT WOOOOOT WOOOOT ALARM RED ALERT RAPE

	my ($coords, $lat, $lon, $today, $tomorrow);

	# Check whether a latitude and longitude were given. Must have at least
	# a dot and one decimal after the dot.
	if ($params =~ m/(-?\d\d?\.\d+)\s(-?\d\d?\d?\.\d+)/)
	{
		$lat = $1;
		$lon = $2;
		$params = 'Coördinaten';
	}
	# Should be a city...
	else
	{
		if ($params eq '')
		{
			# Default city.
			$params = 'Enschede';
		}

		$coords = citycoords($server, $params, $nick, $address, $target);

		if ($coords eq 'Dat gehucht kan niet worden gevonden')
		{
			return $coords;
		}

		($lat, $lon) = split(/ /, $coords);
	}

	$today = join(" ", sun_rise($lon, $lat), '(op)',
	                   sun_set($lon, $lat), '(onder)');
	$tomorrow = join(" ", sun_rise($lon, $lat, undef, +1), '(op)',
	                      sun_set($lon, $lat, undef, +1), '(onder)');

	return join(" ", $today, 'Morgen:', $tomorrow);
	
}

sub validcoords
{
	my ($server, $params, $nick, $address, $target) = @_;

	if ($params =~ m/^-?\d\d?\.\d+\s-?\d\d?\d?\.\d+$/)
	{
		return 'Yes';
	}
	else
	{
		return '';
	}
}

1;
