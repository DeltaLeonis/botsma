#!/usr/bin/perl

package Botsma::WStations;

use strict;
use utf8;
use warnings;

use Math::Trig;
use Math::Vector::Real;
use Math::Vector::Real::kdTree;

# Hash to translate Mercator projected points to their associated weather
# stations.
my %wstations =
(
	'0.0558505360638185 1.05206568677041' => 'Arcen',
	'0.0346156910134567 1.08472395517498' => 'Berkhout',
	'0.0334521498143222 1.06521711010603' => 'Cabauw',
	'0.0381063495174454 1.06899976785199' => 'De Bilt',
	'0.031125032509468 1.09241905934869' => 'Den Helder',
	'0.0503236542814057 1.06805305229234' => 'Deelen',
	'0.062540959045366 1.09870626787915' => 'Eelde',
	'0.0421787960742938 1.05066461707762' => 'Eindhoven',
	'0.048287448456274 1.04368218317806' => 'Ell',
	'0.0337430263874595 1.05393618217869' => 'Gilze Rijen',
	'0.0570140947162456 1.07850616512517' => 'Heino',
	'0.0375245789178781 1.06191648746912' => 'Herwijnen',
	'0.0191986217719376 1.06568930831688' => 'Hoek van Holland',
	'0.0622500824722286 1.08760409320434' => 'Hoogeveen',
	'0.063704517697793 1.06805305229234' => 'Hupsel',
	'0.0558505360638185 1.10697606996133' => 'Lauwersoog',
	'0.048287448456274 1.10113289277356' => 'Leeuwarden',
	'0.0439241253262881 1.07898337789249' => 'Lelystad',
	'0.0485783250294113 1.03581442301121' => 'Maastricht AP',
	'0.0503236542814057 1.08616319936383' => 'Marknesse',
	'0.0727220579841946 1.10016166544324' => 'Nieuw Beerta',
	'0.0253072741539178 1.06474505913644' => 'Rotterdam',
	'0.0308341559363307 1.07469502971304' => 'Schiphol',
	'0.0410152374218667 1.09145456931942' => 'Stavoren',
	'0.0407243433954368 1.1064880812382' => 'Terschelling',
	'0.0680678408277789 1.07374404676733' => 'Twente',
	'0.0247255035543505 1.07136967046034' => 'Valkenburg',
	'0.0340339204138894 1.10210484700204' => 'Vlieland',
	'0.010471975511966 1.05066461707762' => 'Vlissingen',
	'0.0471238898038469 1.05627814132911' => 'Volkel',
	'0.0145444046155219 1.04461096975942' => 'Westdorpe',
	'0.0279252680319093 1.08041607194884' => 'Wijk aan Zee',
	'0.015707963267949 1.05300057801851' => 'Wilhelminadorp',
	'0.0235619449019234 1.05066461707762' => 'Woensdrecht'
);

# The kd-tree with all the weather stations.
# 
# Use a subroutine to build the kd-tree, so we don't have global variables
# other than $tree.
my $tree = _kdtree();

# Create a kd-tree from the points of the %wstations hash.
#
# Returns:
# A kdTree object containing all the weather station locations (as a Mercator
# projection).
sub _kdtree
{
	my ($key, $x, $y);
	# Array containing all the 2D vectors.
	my @v;

	foreach $key (keys %wstations)
	{
		($x, $y) = split(/ /, $key, 2);
		push(@v, V($x, $y));
	}

	return Math::Vector::Real::kdTree->new(@v);
}

# Get the nearest weather station, given a latitude and a longitude.
#
# Parameters:
# $coords A string with the latitude and longitude in degrees, separated by a
#         space.
#
# Returns:
# A string with the name of the nearest weather station.
sub nearest
{
	my ($coords) = @_;

	my ($x, $y, $ix, $d);

	($x, $y) = split(/ /, _mercator($coords), 2);
	($ix, $d) = $tree->find_nearest_neighbor(V($x, $y));

	# Look up the coordinates of the point that find_nearest_neighbor()
	# returned. This returns a Math::Vector::Real, but we can dereference it as
	# an array.
	($x, $y) = @{$tree->at($ix)}; 

	# Now that we have the coordinates, look up the associated weather station.
	return $wstations{join(' ', $x, $y)};
}

# Get the x and y coordinates of a latitude and longitude as a Mercator
# projection.
#
# Parameters:
# $coords A string with the latitude and longitude in degrees, separated by a
#         space.
#
# Returns:
# A string with the x and y coordinates, separated by a space.
sub _mercator
{
    my ($coords) = @_;

    my ($latitude, $longitude, $x, $y);

	($latitude, $longitude) = split(/ /, $coords, 2);

	# Information from http://mathworld.wolfram.com/MercatorProjection.html

	# Place y-axis at longitude 3 instead of at longitude 0. Not really
	# needed... but it's slightly nicer when plotting.
    $x = deg2rad($longitude - 3);

    $latitude = deg2rad($latitude);
    $y = log(tan($latitude) + sec($latitude));

    return join(' ', $x, $y);
}

1;
