package # hide from PAUSE 
    ActorAlias;

BEGIN { unshift @INC, './t/testlib'; }

use strict;
use warnings;

use base 'DBIx::Class::Test::SQLite';

__PACKAGE__->set_table( 'ActorAlias' );

__PACKAGE__->columns( Primary => 'id' );
__PACKAGE__->columns( All     => qw/ actor alias / );
__PACKAGE__->has_a( actor => 'Actor' );
__PACKAGE__->has_a( alias => 'Actor' );

sub create_sql {
	return qq{
		id    INTEGER PRIMARY KEY,
		actor INTEGER,
		alias INTEGER
	}
}

1;

