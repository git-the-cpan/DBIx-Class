use strict;
use warnings;

use Test::More;
use Test::Exception;

plan skip_all => 'boooo';

use lib qw(t/lib);
use DBICTest;

my $track_rs = DBICTest->init_schema->resultset("Track")->search({}, { order_by => 'trackid' });

is $track_rs->slice(0,1)->all, 2;

is $track_rs->slice(0,0)->all, 1;

is $track_rs->slice(5)->all, 1;

is $track_rs->slice(0)->all, 1;

throws_ok
  { $track_rs->slice(1, 0)->next }
  qr/must be a positive integer/
;

is $track_rs->slice()->all, 2;

done_testing;
