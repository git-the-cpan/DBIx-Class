use Test::More;
use lib qw(t/lib);
use DBICTest;
use DBICTest::HelperRels;

require "t/run/20unique.tl";
run_tests(DBICTest->schema);
