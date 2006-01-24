package DBIx::Class::ResultSetProxy;

use base qw/DBIx::Class/;

sub search         { shift->resultset_instance->search(@_);         }
sub search_literal { shift->resultset_instance->search_literal(@_); }
sub search_like    { shift->resultset_instance->search_like(@_);    }
sub count          { shift->resultset_instance->count(@_);          }
sub count_literal  { shift->resultset_instance->count_literal(@_);  }
sub find           { shift->resultset_instance->find(@_);           }
sub create         { shift->resultset_instance->create(@_);         }
sub find_or_create { shift->resultset_instance->find_or_create(@_); }

1;