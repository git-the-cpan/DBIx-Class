###
### This version is rather 5.8-centric, because DBIC itself is 5.8
### It certainly can be rewritten to degrade well on 5.6
###


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
use Config;
use File::Find 'find';
use Module::Runtime 'module_notional_filename';
use List::Util 'max';
use ExtUtils::MakeMaker;
use DBICTest::Util 'visit_namespaces';

# load these two to pull in the t/lib armada
use DBICTest;
use DBICTest::Schema;

# do !!!NOT!!! use Module::Runtime's require_module - it breaks CORE::require
sub req_mod ($) {
  # trap deprecation warnings and whatnot
  local $SIG{__WARN__} = sub {};
  local $@;
  eval "require $_[0]";
}

sub say_err {
  print STDERR "\n", @_, "\n";
}

my @lib_display_order = qw(
  sitearch
  sitelib
  vendorarch
  vendorlib
  archlib
  privlib
);
my $lib_paths = {
  (map
    { $Config{$_} ? ( $_ => $Config{"${_}exp"} || $Config{$_} ) : () }
    @lib_display_order
  ),

  # synthetic, for display
  './lib' => 'lib',
};

sub describe_fn {
  my $fn = shift;

  $lib_paths->{$_} and $fn =~ s/^\Q$lib_paths->{$_}/<<$_>>/ and last
    for @lib_display_order;

  $fn;
}

sub md5_of_fn {
  # we already checked for -r/-f, just bail if can't open
  open my $fh, '<:raw', $_[0] or return '';
  require Digest::MD5;
  Digest::MD5->new->addfile($fh)->hexdigest;
}

# first run through lib and *try* to load anything we can find
# within our own project
find({
  wanted => sub {
    -f $_ or return;

    # can't just `require $fn`, as we need %INC to be
    # populated properly
    my ($mod) = $_ =~ /^ lib [\/\\] (.+) \.pm $/x
      or return;

    req_mod join ('::', File::Spec->splitdir($mod));
  },
  no_chdir => 1,
}, 'lib' );

# now run through OptDeps and attempt loading everything else
#
# some things needs to be sorted before other things
# positive - load first
# negative - load last
my $load_weights = {
  # Make sure oracle is tried last - some clients (e.g. 10.2) have symbol
  # clashes with libssl, and will segfault everything coming after them
  "DBD::Oracle" => -999,
};
req_mod $_ for sort
  { ($load_weights->{$b}||0) <=> ($load_weights->{$a}||0) }
  keys %{
    DBIx::Class::Optional::Dependencies->req_list_for([
      keys %{DBIx::Class::Optional::Dependencies->req_group_list}
    ])
  }
;

my $has_versionpm = eval { require version };

# at this point we've loaded everything we ever could, let's drill through
# the *ENTIRE* symtable and build a map of versions
my $version_list = { perl => $] };
visit_namespaces( action => sub {
  my $pkg = shift;

  # keep going, but nothing to see here
  return 1 if $pkg eq 'main';

  # private - not interested
  return 0 if $pkg =~ / (?: ^ | :: ) _ /x;

  no strict 'refs';
  # that would be some synthetic class, or a custom sub VERSION
  return 1 unless defined ${"${pkg}::VERSION"};

  # make sure a version can be extracted, be noisy when it doesn't work
  # do this even if we are throwing away the result below in lieu of EUMM
  my $mod_ver = eval { $pkg->VERSION };
  if (my $err = $@) {
    $err =~ s/^/  /mg;
    say_err
      "Calling `$pkg->VERSION` resulted in an exception, which should never "
    . "happen - please file a bug with the distribution containing $pkg. "
    . "Follows the full text of the exception:\n\n$err\n"
    ;
  }
  elsif( ! defined $mod_ver ) {
    say_err
      "Calling `$pkg->VERSION` returned 'undef', which should never "
    . "happen - please file a bug with the distribution containing $pkg."
    ;

  }
  elsif( ! length $mod_ver ) {
    say_err
      "Calling `$pkg->VERSION` returned the empty string '', which should never "
    . "happen - please file a bug with the distribution containing $pkg."
    ;
    undef $mod_ver;
  }

  # if this is a real file - extract the version via EUMM whenever possible
  my $fn = $INC{module_notional_filename($pkg)};

  my $eumm_ver = eval { MM->parse_version( $fn ) }
    if $fn and  -f $fn and -r $fn;

  if (
    $has_versionpm
      and
    defined $eumm_ver
      and
    defined $mod_ver
      and
    $eumm_ver ne $mod_ver
      and
    (
      ( eval { version->parse( do { (my $v = $eumm_ver) =~ s/_//g; $v } ) } || 0 )
        !=
      ( eval { version->parse( do { (my $v = $mod_ver) =~ s/_//g; $v } ) } || 0 )
    )
  ) {
    say_err
      "Mismatch of versions '$mod_ver' and '$eumm_ver', obtained respectively "
    . "via `$pkg->VERSION` and parsing the version out of @{[ describe_fn $fn ]} "
    . "with ExtUtils::MakeMaker\@@{[ ExtUtils::MakeMaker->VERSION ]}. "
    . "This should never happen - please check whether this is still present "
    . "in the latest version, and then file a bug with the distribution "
    . "containing $pkg."
    ;
  }

  if( defined $eumm_ver ) {
    $version_list->{$pkg} = $eumm_ver;
  }
  elsif( defined $mod_ver ) {
    $version_list->{$pkg} = $mod_ver;
  }

  1;
});

# compress identical versions as close to the root as we can
for my $mod ( sort { length($b) <=> length($a) } keys %$version_list ) {
  my $parent = $mod;

  while ( $parent =~ s/ :: (?: . (?! :: ) )+ $ //x ) {
    $version_list->{$parent}
      and
    $version_list->{$parent} eq $version_list->{$mod}
      and
    ( ( delete $version_list->{$mod} ) or 1 )
      and
    last
  }
}

ok 1, (scalar keys %$version_list) . " distinctly versioned modules";

# sort stuff into @INC segments
my $segments;

MODULE:
for my $mod ( sort { lc($a) cmp lc($b) } keys %$version_list ) {
  my $fn = $INC{module_notional_filename($mod)};

  my $tuple = [
    $mod,
    ( ( $fn && -f $fn && -r $fn ) ? $fn : undef )
  ];


  if ($fn) {
    for my $lib (@lib_display_order, './lib') {
      if ( $lib_paths->{$lib} and index($fn, $lib_paths->{$lib}) == 0 ) {
        push @{$segments->{$lib}}, $tuple;
        next MODULE;
      }
    }
  }

  # fallthrough for anything without a physical filename, or unknown lib
  push @{$segments->{''}}, $tuple;
}

# diag the result out
my $max_ver = max map { length $_ } values %$version_list;
my $max_mod = max map { length $_ } keys %$version_list;

my $diag = "\n\nVersions of all loadable modules within the configure/build/test/runtime dependency chains present on this system (both core and optional)\n\n";
for my $seg ( '', @lib_display_order, './lib' ) {
  next unless $segments->{$seg};

  $diag .= sprintf "=== %s ===\n\n",
    $seg
      ? "Modules found in " . ( $Config{$seg} ? "\$Config{$seg}" : $seg )
      : 'Misc'
  ;

  $diag .= sprintf (
    "   %*s  %*s%s\n",
    $max_ver => $version_list->{$_->[0]},
    -$max_mod => $_->[0],
    ( ( $ENV{AUTOMATED_TESTING} and $_->[1] )
      ? "  [ MD5: @{[ md5_of_fn( $_->[1] ) ]} ]"
      : ''
    ),
  ) for @{$segments->{$seg}};

  $diag .= "\n\n"
}

diag $diag;

done_testing;
