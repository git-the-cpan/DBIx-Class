use strict;
use warnings;

use Test::More;
use lib qw(t/lib);
use DBICTest;

my ($dsn, $user, $pass) = @ENV{map { "DBICTEST_DB2_400_${_}" } qw/DSN USER PASS/};

#warn "$dsn $user $pass";

# Probably best to pass the DBQ option in the DSN to specify a specific
# libray.  Something like:
# DBICTEST_DB2_400_DSN='dbi:ODBC:dsn=MyAS400;DBQ=MYLIB'
plan skip_all => 'Set $ENV{DBICTEST_DB2_400_DSN}, _USER and _PASS to run this test'
  unless ($dsn && $user);

plan tests => 6;

my $schema = DBICTest::Schema->connect($dsn, $user, $pass);

my $dbh = $schema->storage->dbh;

eval { $dbh->do("DROP TABLE artist") };

$dbh->do(<<'');
CREATE TABLE artist (
    artistid INTEGER GENERATED BY DEFAULT AS IDENTITY (START WITH 1, INCREMENT BY 1),
    name VARCHAR(255),
    rank INTEGER default 13 not null,
    charfield CHAR(10)
)

# Just to test loading, already in Core
$schema->class('Artist')->load_components('PK::Auto');

# test primary key handling
my $new = $schema->resultset('Artist')->create({ name => 'foo' });
ok($new->artistid, "Auto-PK worked");

# test LIMIT support
for (1..6) {
    $schema->resultset('Artist')->create({ name => 'Artist ' . $_ });
}
my $it = $schema->resultset('Artist')->search( {},
    { rows => 3,
      order_by => 'artistid'
      }
);
is( $it->count, 3, "LIMIT count ok" );
is( $it->next->name, "foo", "iterator->next ok" );
$it->next;
is( $it->next->name, "Artist 2", "iterator->next ok" );
is( $it->next, undef, "next past end of resultset ok" );

my $test_type_info = {
    'artistid' => {
        'data_type' => 'INTEGER',
        'is_nullable' => 0,
        'size' => 10
    },
    'name' => {
        'data_type' => 'VARCHAR',
        'is_nullable' => 1,
        'size' => 255
    },
    'rank' => {
        'data_type' => 'INTEGER',
        'is_nullable' => 0,
        'size' => 10,
    },
    'charfield' => {
        'data_type' => 'CHAR',
        'is_nullable' => 1,
        'size' => 10 
    },
};


my $type_info = $schema->storage->columns_info_for('artist');
is_deeply($type_info, $test_type_info, 'columns_info_for - column data types');

# clean up our mess
END {
    my $dbh = eval { $schema->storage->_dbh };
    $dbh->do("DROP TABLE artist") if $dbh;
}
