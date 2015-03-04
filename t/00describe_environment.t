BEGIN {
  if ($] < 5.010) {

    # Pre-5.10 perls pollute %INC on unsuccesfull module
    # require, making it appear as if the module is already
    # loaded on subsequent require()s
    # Can't seem to find the exact RT/perldelta entry
    #
    # The reason we can't just use a sane, clean loader, is because
    # if a Module require()s another module the %INC will still
    # get filled with crap and we are back to square one. A global
    # fix is really the only way for this test, as we try to load
    # each available module separately, and have no control (nor
    # knowledge) over their common dependencies.
    #
    # we want to do this here, in the very beginning, before even
    # warnings/strict are loaded

    unshift @INC, 't/lib';
    require DBICTest::Util::OverrideRequire;

    DBICTest::Util::OverrideRequire::override_global_require( sub {
      my $res = eval { $_[0]->() };
      if ($@ ne '') {
        delete $INC{$_[1]};
        die $@;
      }
      return $res;
    } );
  }
}

# Explicitly add 'lib' to the front of INC - this way we will
# know without ambiguity what was loaded from the local untar
# and what came from elsewhere
use lib qw(lib t/lib);

use strict;
use warnings;

use Test::More;
use File::Find 'find';
use Module::Runtime 'module_notional_filename';
use List::Util 'max';

# load these two to pull in the t/lib armada
use DBICTest;
use DBICTest::Schema;
use DBICTest::Util 'visit_namespaces';

# first run through lib and *try* to load anything we can find
find({
  wanted => sub {
    -f $_ or return;

    # can't just `require $fn`, as we need %INC to be
    # populated properly
    my ($mod) = $_ =~ /^ lib [\/\\] (.+) \.pm $/x
      or return;

    # trap deprecation warnings and whatnot
    local $SIG{__WARN__} = sub {};

    eval( 'require ' . join ('::', File::Spec->splitdir($mod)) );
  },
  no_chdir => 1,
}, 'lib' );

# now run through OptDeps and get everything else
eval "require $_" for keys %{
  DBIx::Class::Optional::Dependencies->req_list_for([
    keys %{DBIx::Class::Optional::Dependencies->req_group_list}
  ])
};

# at this point we've loaded everything we ever could, let's drill through
# the *ENTIRE* symtable and build a map of versions
my $v = { perl => $] };
visit_namespaces( action => sub {
  my $pkg = shift;

  # keep going, but nothing to see here
  return 1 if $pkg eq 'main';

  # private - not interested
  return 0 if $pkg =~ / (?: ^ | :: ) _ /x;

  no strict 'refs';
  if (
    defined ${"${pkg}::VERSION"}
      and
    # throw away anything that came from our lib
    ( $INC{ module_notional_filename $pkg }||'' ) !~ /^ lib [\\\/] /x
  ) {
    $v->{$pkg} = $pkg->VERSION
  }

  1;
});

# compress identical versions as close to the root as we can
for my $mod ( sort { length($b) <=> length($a) } keys %$v ) {
  my $parent = $mod;

  while ( $parent =~ s/ :: (?: . (?! :: ) )+ $ //x ) {
    $v->{$parent}
      and
    $v->{$parent} eq $v->{$mod}
      and
    ( ( delete $v->{$mod} ) or 1 )
      and
    last
  }
}

ok 1, (scalar keys %$v) . " distinctly versioned modules";

# tadaaaa
my $max_mod = max map { length $_ } keys %$v;
my $max_ver = max map { length $_ } values %$v;

my $diag = "\nAvailable versions of core and optional dependency chains\n\n";
$diag .= sprintf (
  " %*s  %*s\n",
  $max_ver  => $v->{$_},
  -$max_mod => $_
) for sort keys %$v;

diag $diag;

done_testing;
