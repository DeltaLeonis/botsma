use strict;
use utf8;

use Botsma::Encoding;

print "Dit is een testje van wat vage encoding trucjes..\n";
print "Chef: " . Botsma::Encoding::encode('chef', 'Dit is een testje van wat vage encoding trucjes..') . "\n";
print "Ali: " . Botsma::Encoding::encode('ali', 'Dit is een testje van wat vage encoding trucjes..') . "\n";
print "l33t: " . Botsma::Encoding::encode('l33t', 'Dit is een testje van wat vage encoding trucjes..') . "\n";
print "onbestaand: " . Botsma::Encoding::encode('onbestaand', 'Dit is een testje van wat vage encoding trucjes..') . "\n";
