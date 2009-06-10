use warnings;  

use Test::More;
use Test::Exception;
use lib qw(t/lib);
use DBICTest;
use Data::Dumper;

my $schema = DBICTest->init_schema();

my $orig_debug = $schema->storage->debug;

use IO::File;

BEGIN {
    eval "use DBD::SQLite";
    plan $@
        ? ( skip_all => 'needs DBD::SQLite for testing' )
        : ( tests => 3 );
}

# bug in 0.07000 caused attr (join/prefetch) to be modifed by search
# so we check the search & attr arrays are not modified
my $search = { 'artist.name' => 'Caterwauler McCrae' };
my $attr = { prefetch => [ qw/artist liner_notes/ ],
             order_by => 'me.cdid' };
my $search_str = Dumper($search);
my $attr_str = Dumper($attr);

my $rs = $schema->resultset("CD")->search($search, $attr);

is(Dumper($search), $search_str, 'Search hash untouched after search()');
is(Dumper($attr), $attr_str, 'Attribute hash untouched after search()');
cmp_ok($rs + 0, '==', 3, 'Correct number of records returned');