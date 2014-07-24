## ----------------------------------------------------------------------------
## Tests for the $resultset->populate method.
##
## GOALS:  We need to test the method for both void and array context for all
## the following relationship types: belongs_to, has_many.  Additionally we
## need to test each of those for both specified PK's and autogenerated PK's
##
## Also need to test some stuff that should generate errors.
## ----------------------------------------------------------------------------

use strict;
use warnings;

use Test::More;
use Test::Warn;
use lib qw(t/lib);
use DBICTest;


## ----------------------------------------------------------------------------
## Get a Schema and some ResultSets we can play with.
## ----------------------------------------------------------------------------

my $schema  = DBICTest->init_schema();
my $art_rs  = $schema->resultset('Artist');
my $cd_rs  = $schema->resultset('CD');

my $restricted_art_rs  = $art_rs->search({ -and => [ rank => 42, charfield => { '=', \['(SELECT MAX(artistid) FROM artist) + ?', 6] } ] });

ok( $schema, 'Got a Schema object');
ok( $art_rs, 'Got Good Artist Resultset');
ok( $cd_rs, 'Got Good CD Resultset');


## ----------------------------------------------------------------------------
## Schema populate Tests
## ----------------------------------------------------------------------------

SCHEMA_POPULATE1: {

  # throw a monkey wrench
  my $post_jnap_monkeywrench = $schema->resultset('Artist')->find(1)->update({ name => undef });

  warnings_exist { $schema->populate('Artist', [

    [qw/name cds/],
    ["001First Artist", [
      {title=>"001Title1", year=>2000},
      {title=>"001Title2", year=>2001},
      {title=>"001Title3", year=>2002},
    ]],
    ["002Second Artist", []],
    ["003Third Artist", [
      {title=>"003Title1", year=>2005},
    ]],
    [undef, [
      {title=>"004Title1", year=>2010}
    ]],
  ]) } qr/\QFast-path populate() of non-uniquely identifiable rows with related data is not possible/;

  isa_ok $schema, 'DBIx::Class::Schema';

  my ( $preexisting_undef, $artist1, $artist2, $artist3, $undef ) = $schema->resultset('Artist')->search({
    name=>["001First Artist","002Second Artist","003Third Artist", undef]},
    {order_by => { -asc => 'artistid' }})->all;

  isa_ok  $artist1, 'DBICTest::Artist';
  isa_ok  $artist2, 'DBICTest::Artist';
  isa_ok  $artist3, 'DBICTest::Artist';
  isa_ok  $undef, 'DBICTest::Artist';

  ok $artist1->name eq '001First Artist', "Got Expected Artist Name for Artist001";
  ok $artist2->name eq '002Second Artist', "Got Expected Artist Name for Artist002";
  ok $artist3->name eq '003Third Artist', "Got Expected Artist Name for Artist003";
  ok !defined $undef->name, "Got Expected Artist Name for Artist004";

  ok $artist1->cds->count eq 3, "Got Right number of CDs for Artist1";
  ok $artist2->cds->count eq 0, "Got Right number of CDs for Artist2";
  ok $artist3->cds->count eq 1, "Got Right number of CDs for Artist3";
  ok $undef->cds->count eq 1, "Got Right number of CDs for Artist4";

  $post_jnap_monkeywrench->delete;

  ARTIST1CDS: {

    my ($cd1, $cd2, $cd3) = $artist1->cds->search(undef, {order_by=>'year ASC'});

    isa_ok $cd1, 'DBICTest::CD';
    isa_ok $cd2, 'DBICTest::CD';
    isa_ok $cd3, 'DBICTest::CD';

    ok $cd1->year == 2000;
    ok $cd2->year == 2001;
    ok $cd3->year == 2002;

    ok $cd1->title eq '001Title1';
    ok $cd2->title eq '001Title2';
    ok $cd3->title eq '001Title3';
  }

  ARTIST3CDS: {

    my ($cd1) = $artist3->cds->search(undef, {order_by=>'year ASC'});

    isa_ok $cd1, 'DBICTest::CD';

    ok $cd1->year == 2005;
    ok $cd1->title eq '003Title1';
  }

  ARTIST4CDS: {

    my ($cd1) = $undef->cds->search(undef, {order_by=>'year ASC'});

    isa_ok $cd1, 'DBICTest::CD';

    ok $cd1->year == 2010;
    ok $cd1->title eq '004Title1';
  }

  ## Need to do some cleanup so that later tests don't get borked

  $undef->delete;
}


## ----------------------------------------------------------------------------
## Array context tests
## ----------------------------------------------------------------------------

ARRAY_CONTEXT: {

  ## These first set of tests are cake because array context just delegates
  ## all its processing to $resultset->create

  HAS_MANY_NO_PKS: {

    ## This first group of tests checks to make sure we can call populate
    ## with the parent having many children and let the keys be automatic

    my $artists = [
      {
        name => 'Angsty-Whiny Girl',
        cds => [
          { title => 'My First CD', year => 2006 },
          { title => 'Yet More Tweeny-Pop crap', year => 2007 },
        ],
      },
      {
        name => 'Manufactured Crap',
      },
      {
        name => 'Like I Give a Damn',
        cds => [
          { title => 'My parents sold me to a record company' ,year => 2005 },
          { title => 'Why Am I So Ugly?', year => 2006 },
          { title => 'I Got Surgery and am now Popular', year => 2007 }
        ],
      },
      {
        name => 'Formerly Named',
        cds => [
          { title => 'One Hit Wonder', year => 2006 },
        ],
      },
    ];

    ## Get the result row objects.

    my ($girl, $crap, $damn, $formerly) = $art_rs->populate($artists);

    ## Do we have the right object?

    isa_ok( $crap, 'DBICTest::Artist', "Got 'Artist'");
    isa_ok( $girl, 'DBICTest::Artist', "Got 'Artist'");
    isa_ok( $damn, 'DBICTest::Artist', "Got 'Artist'");
    isa_ok( $formerly, 'DBICTest::Artist', "Got 'Artist'");

    ## Find the expected information?

    ok( $crap->name eq 'Manufactured Crap', "Got Correct name for result object");
    ok( $girl->name eq 'Angsty-Whiny Girl', "Got Correct name for result object");
    ok( $damn->name eq 'Like I Give a Damn', "Got Correct name for result object");
    ok( $formerly->name eq 'Formerly Named', "Got Correct name for result object");

    ## Create the expected children sub objects?

    ok( $crap->cds->count == 0, "got Expected Number of Cds");
    ok( $girl->cds->count == 2, "got Expected Number of Cds");
    ok( $damn->cds->count == 3, "got Expected Number of Cds");
    ok( $formerly->cds->count == 1, "got Expected Number of Cds");

    ## Did the cds get expected information?

    my ($cd1, $cd2) = $girl->cds->search({},{order_by=>'year'});

    ok( $cd1->title eq "My First CD", "Got Expected CD Title");
    ok( $cd2->title eq "Yet More Tweeny-Pop crap", "Got Expected CD Title");
  }

  HAS_MANY_WITH_PKS: {

    ## This group tests the ability to specify the PK in the parent and let
    ## DBIC transparently pass the PK down to the Child and also let's the
    ## child create any other needed PK's for itself.

    my $aid    =  $art_rs->get_column('artistid')->max || 0;

    my $first_aid = ++$aid;

    my $artists = [
      {
        artistid => $first_aid,
        name => 'PK_Angsty-Whiny Girl',
        cds => [
          { artist => $first_aid, title => 'PK_My First CD', year => 2006 },
          { artist => $first_aid, title => 'PK_Yet More Tweeny-Pop crap', year => 2007 },
        ],
      },
      {
        artistid => ++$aid,
        name => 'PK_Manufactured Crap',
      },
      {
        artistid => ++$aid,
        name => 'PK_Like I Give a Damn',
        cds => [
          { title => 'PK_My parents sold me to a record company' ,year => 2005 },
          { title => 'PK_Why Am I So Ugly?', year => 2006 },
          { title => 'PK_I Got Surgery and am now Popular', year => 2007 }
        ],
      },
      {
        artistid => ++$aid,
        name => 'PK_Formerly Named',
        cds => [
          { title => 'PK_One Hit Wonder', year => 2006 },
        ],
      },
    ];

    ## Get the result row objects.

    my ($girl, $crap, $damn, $formerly) = $art_rs->populate($artists);

    ## Do we have the right object?

    isa_ok( $crap, 'DBICTest::Artist', "Got 'Artist'");
    isa_ok( $girl, 'DBICTest::Artist', "Got 'Artist'");
    isa_ok( $damn, 'DBICTest::Artist', "Got 'Artist'");
    isa_ok( $formerly, 'DBICTest::Artist', "Got 'Artist'");

    ## Find the expected information?

    ok( $crap->name eq 'PK_Manufactured Crap', "Got Correct name for result object");
    ok( $girl->name eq 'PK_Angsty-Whiny Girl', "Got Correct name for result object");
    ok( $girl->artistid == $first_aid, "Got Correct artist PK for result object");
    ok( $damn->name eq 'PK_Like I Give a Damn', "Got Correct name for result object");
    ok( $formerly->name eq 'PK_Formerly Named', "Got Correct name for result object");

    ## Create the expected children sub objects?

    ok( $crap->cds->count == 0, "got Expected Number of Cds");
    ok( $girl->cds->count == 2, "got Expected Number of Cds");
    ok( $damn->cds->count == 3, "got Expected Number of Cds");
    ok( $formerly->cds->count == 1, "got Expected Number of Cds");

    ## Did the cds get expected information?

    my ($cd1, $cd2) = $girl->cds->search({},{order_by=>'year ASC'});

    ok( $cd1->title eq "PK_My First CD", "Got Expected CD Title");
    ok( $cd2->title eq "PK_Yet More Tweeny-Pop crap", "Got Expected CD Title");
  }

  BELONGS_TO_NO_PKs: {

    ## Test from a belongs_to perspective, should create artist first,
    ## then CD with artistid.  This test we let the system automatically
    ## create the PK's.  Chances are good you'll use it this way mostly.

    my $cds = [
      {
        title => 'Some CD3',
        year => '1997',
        artist => { name => 'Fred BloggsC'},
      },
      {
        title => 'Some CD4',
        year => '1997',
        artist => { name => 'Fred BloggsD'},
      },
    ];

    my ($cdA, $cdB) = $cd_rs->populate($cds);


    isa_ok($cdA, 'DBICTest::CD', 'Created CD');
    isa_ok($cdA->artist, 'DBICTest::Artist', 'Set Artist');
    is($cdA->artist->name, 'Fred BloggsC', 'Set Artist to FredC');


    isa_ok($cdB, 'DBICTest::CD', 'Created CD');
    isa_ok($cdB->artist, 'DBICTest::Artist', 'Set Artist');
    is($cdB->artist->name, 'Fred BloggsD', 'Set Artist to FredD');
  }

  BELONGS_TO_WITH_PKs: {

    ## Test from a belongs_to perspective, should create artist first,
    ## then CD with artistid.  This time we try setting the PK's

    my $aid  = $art_rs->get_column('artistid')->max || 0;

    my $cds = [
      {
        title => 'Some CD3',
        year => '1997',
        artist => { artistid=> ++$aid, name => 'Fred BloggsE'},
      },
      {
        title => 'Some CD4',
        year => '1997',
        artist => { artistid=> ++$aid, name => 'Fred BloggsF'},
      },
    ];

    my ($cdA, $cdB) = $cd_rs->populate($cds);

    isa_ok($cdA, 'DBICTest::CD', 'Created CD');
    isa_ok($cdA->artist, 'DBICTest::Artist', 'Set Artist');
    is($cdA->artist->name, 'Fred BloggsE', 'Set Artist to FredE');

    isa_ok($cdB, 'DBICTest::CD', 'Created CD');
    isa_ok($cdB->artist, 'DBICTest::Artist', 'Set Artist');
    is($cdB->artist->name, 'Fred BloggsF', 'Set Artist to FredF');
    ok($cdB->artist->artistid == $aid, "Got Expected Artist ID");
  }

  WITH_COND_FROM_RS: {

    my ($more_crap) = $restricted_art_rs->populate([
      {
        name => 'More Manufactured Crap',
      },
    ]);

    ## Did it use the condition in the resultset?
    $more_crap->discard_changes;
    cmp_ok( $more_crap->rank, '==', 42, "Got Correct rank for result object");
    cmp_ok( $more_crap->charfield, '==', $more_crap->id + 5, "Got Correct charfield for result object");
  }
}


## ----------------------------------------------------------------------------
## Void context tests
## ----------------------------------------------------------------------------

VOID_CONTEXT: {

  ## All these tests check the ability to use populate without asking for
  ## any returned resultsets.  This uses bulk_insert as much as possible
  ## in order to increase speed.

  HAS_MANY_WITH_PKS: {

    ## This first group of tests checks to make sure we can call populate
    ## with the parent having many children and the parent PK is set

    my $aid = $art_rs->get_column('artistid')->max || 0;

    my $first_aid = ++$aid;

    my $artists = [
      {
        artistid => $first_aid,
        name => 'VOID_PK_Angsty-Whiny Girl',
        cds => [
          { artist => $first_aid, title => 'VOID_PK_My First CD', year => 2006 },
          { artist => $first_aid, title => 'VOID_PK_Yet More Tweeny-Pop crap', year => 2007 },
        ],
      },
      {
        artistid => ++$aid,
        name => 'VOID_PK_Manufactured Crap',
      },
      {
        artistid => ++$aid,
        name => 'VOID_PK_Like I Give a Damn',
        cds => [
          { title => 'VOID_PK_My parents sold me to a record company' ,year => 2005 },
          { title => 'VOID_PK_Why Am I So Ugly?', year => 2006 },
          { title => 'VOID_PK_I Got Surgery and am now Popular', year => 2007 }
        ],
      },
      {
        artistid => ++$aid,
        name => 'VOID_PK_Formerly Named',
        cds => [
          { title => 'VOID_PK_One Hit Wonder', year => 2006 },
        ],
      },
      {
        artistid => ++$aid,
        name => undef,
        cds => [
          { title => 'VOID_PK_Zundef test', year => 2006 },
        ],
      },
    ];

    ## Get the result row objects.

    $art_rs->populate($artists);

    my ($undef, $girl, $formerly, $damn, $crap) = $art_rs->search(

      {name=>[ map { $_->{name} } @$artists]},
      {order_by=>'name ASC'},
    );

    ## Do we have the right object?

    isa_ok( $crap, 'DBICTest::Artist', "Got 'Artist'");
    isa_ok( $girl, 'DBICTest::Artist', "Got 'Artist'");
    isa_ok( $damn, 'DBICTest::Artist', "Got 'Artist'");
    isa_ok( $formerly, 'DBICTest::Artist', "Got 'Artist'");
    isa_ok( $undef, 'DBICTest::Artist', "Got 'Artist'");

    ## Find the expected information?

    ok( $crap->name eq 'VOID_PK_Manufactured Crap', "Got Correct name 'VOID_PK_Manufactured Crap' for result object");
    ok( $girl->name eq 'VOID_PK_Angsty-Whiny Girl', "Got Correct name for result object");
    ok( $damn->name eq 'VOID_PK_Like I Give a Damn', "Got Correct name for result object");
    ok( $formerly->name eq 'VOID_PK_Formerly Named', "Got Correct name for result object");
    ok( !defined $undef->name, "Got Correct name 'is undef' for result object");

    ## Create the expected children sub objects?
    ok( $crap->can('cds'), "Has cds relationship");
    ok( $girl->can('cds'), "Has cds relationship");
    ok( $damn->can('cds'), "Has cds relationship");
    ok( $formerly->can('cds'), "Has cds relationship");
    ok( $undef->can('cds'), "Has cds relationship");

    ok( $crap->cds->count == 0, "got Expected Number of Cds");
    ok( $girl->cds->count == 2, "got Expected Number of Cds");
    ok( $damn->cds->count == 3, "got Expected Number of Cds");
    ok( $formerly->cds->count == 1, "got Expected Number of Cds");
    ok( $undef->cds->count == 1, "got Expected Number of Cds");

    ## Did the cds get expected information?

    my ($cd1, $cd2) = $girl->cds->search({},{order_by=>'year ASC'});

    ok( $cd1->title eq "VOID_PK_My First CD", "Got Expected CD Title");
    ok( $cd2->title eq "VOID_PK_Yet More Tweeny-Pop crap", "Got Expected CD Title");
  }


  BELONGS_TO_WITH_PKs: {

    ## Test from a belongs_to perspective, should create artist first,
    ## then CD with artistid.  This time we try setting the PK's

    my $aid  = $art_rs->get_column('artistid')->max || 0;

    my $cds = [
      {
        title => 'Some CD3B',
        year => '1997',
        artist => { artistid=> ++$aid, name => 'Fred BloggsCB'},
      },
      {
        title => 'Some CD4B',
        year => '1997',
        artist => { artistid=> ++$aid, name => 'Fred BloggsDB'},
      },
    ];

    warnings_exist {
      $cd_rs->populate($cds)
    } qr/\QFast-path populate() of belongs_to relationship data is not possible/;

    my ($cdA, $cdB) = $cd_rs->search(
      {title=>[sort map {$_->{title}} @$cds]},
      {order_by=>'title ASC'},
    );

    isa_ok($cdA, 'DBICTest::CD', 'Created CD');
    isa_ok($cdA->artist, 'DBICTest::Artist', 'Set Artist');
    is($cdA->artist->name, 'Fred BloggsCB', 'Set Artist to FredCB');

    isa_ok($cdB, 'DBICTest::CD', 'Created CD');
    isa_ok($cdB->artist, 'DBICTest::Artist', 'Set Artist');
    is($cdB->artist->name, 'Fred BloggsDB', 'Set Artist to FredDB');
    ok($cdB->artist->artistid == $aid, "Got Expected Artist ID");
  }

  BELONGS_TO_NO_PKs: {

    ## Test from a belongs_to perspective, should create artist first,
    ## then CD with artistid.

    my $cds = [
      {
        title => 'Some CD3BB',
        year => '1997',
        artist => { name => 'Fred BloggsCBB'},
      },
      {
        title => 'Some CD4BB',
        year => '1997',
        artist => { name => 'Fred BloggsDBB'},
      },
      {
        title => 'Some CD5BB',
        year => '1997',
        artist => { name => undef},
      },
    ];

    warnings_exist {
      $cd_rs->populate($cds);
    } qr/\QFast-path populate() of belongs_to relationship data is not possible/;

    my ($cdA, $cdB, $cdC) = $cd_rs->search(
      {title=>[sort map {$_->{title}} @$cds]},
      {order_by=>'title ASC'},
    );

    isa_ok($cdA, 'DBICTest::CD', 'Created CD');
    isa_ok($cdA->artist, 'DBICTest::Artist', 'Set Artist');
    is($cdA->title, 'Some CD3BB', 'Found Expected title');
    is($cdA->artist->name, 'Fred BloggsCBB', 'Set Artist to FredCBB');

    isa_ok($cdB, 'DBICTest::CD', 'Created CD');
    isa_ok($cdB->artist, 'DBICTest::Artist', 'Set Artist');
    is($cdB->title, 'Some CD4BB', 'Found Expected title');
    is($cdB->artist->name, 'Fred BloggsDBB', 'Set Artist to FredDBB');

    isa_ok($cdC, 'DBICTest::CD', 'Created CD');
    isa_ok($cdC->artist, 'DBICTest::Artist', 'Set Artist');
    is($cdC->title, 'Some CD5BB', 'Found Expected title');
    is( $cdC->artist->name, undef, 'Set Artist to something undefined');
  }


  HAS_MANY_NO_PKS: {

    ## This first group of tests checks to make sure we can call populate
    ## with the parent having many children and let the keys be automatic

    my $artists = [
      {
        name => 'VOID_Angsty-Whiny Girl',
        cds => [
          { title => 'VOID_My First CD', year => 2006 },
          { title => 'VOID_Yet More Tweeny-Pop crap', year => 2007 },
        ],
      },
      {
        name => 'VOID_Manufactured Crap',
      },
      {
        name => 'VOID_Like I Give a Damn',
        cds => [
          { title => 'VOID_My parents sold me to a record company' ,year => 2005 },
          { title => 'VOID_Why Am I So Ugly?', year => 2006 },
          { title => 'VOID_I Got Surgery and am now Popular', year => 2007 }
        ],
      },
      {
        name => 'VOID_Formerly Named',
        cds => [
          { title => 'VOID_One Hit Wonder', year => 2006 },
        ],
      },
    ];

    ## Get the result row objects.

    $art_rs->populate($artists);

    my ($girl, $formerly, $damn, $crap) = $art_rs->search(
      {name=>[sort map {$_->{name}} @$artists]},
      {order_by=>'name ASC'},
    );

    ## Do we have the right object?

    isa_ok( $crap, 'DBICTest::Artist', "Got 'Artist'");
    isa_ok( $girl, 'DBICTest::Artist', "Got 'Artist'");
    isa_ok( $damn, 'DBICTest::Artist', "Got 'Artist'");
    isa_ok( $formerly, 'DBICTest::Artist', "Got 'Artist'");

    ## Find the expected information?

    ok( $crap->name eq 'VOID_Manufactured Crap', "Got Correct name for result object");
    ok( $girl->name eq 'VOID_Angsty-Whiny Girl', "Got Correct name for result object");
    ok( $damn->name eq 'VOID_Like I Give a Damn', "Got Correct name for result object");
    ok( $formerly->name eq 'VOID_Formerly Named', "Got Correct name for result object");

    ## Create the expected children sub objects?
    ok( $crap->can('cds'), "Has cds relationship");
    ok( $girl->can('cds'), "Has cds relationship");
    ok( $damn->can('cds'), "Has cds relationship");
    ok( $formerly->can('cds'), "Has cds relationship");

    ok( $crap->cds->count == 0, "got Expected Number of Cds");
    ok( $girl->cds->count == 2, "got Expected Number of Cds");
    ok( $damn->cds->count == 3, "got Expected Number of Cds");
    ok( $formerly->cds->count == 1, "got Expected Number of Cds");

    ## Did the cds get expected information?

    my ($cd1, $cd2) = $girl->cds->search({},{order_by=>'year ASC'});

    ok($cd1, "Got a got CD");
    ok($cd2, "Got a got CD");
    ok( $cd1->title eq "VOID_My First CD", "Got Expected CD Title");
    ok( $cd2->title eq "VOID_Yet More Tweeny-Pop crap", "Got Expected CD Title");
  }

  WITH_COND_FROM_RS: {

    $restricted_art_rs->populate([
      {
        name => 'VOID More Manufactured Crap',
      },
    ]);

    my $more_crap = $art_rs->search({
      name => 'VOID More Manufactured Crap'
    })->first;

    ## Did it use the condition in the resultset?
    $more_crap->discard_changes;
    cmp_ok( $more_crap->rank, '==', 42, "Got Correct rank for result object");
    cmp_ok( $more_crap->charfield, '==', $more_crap->id + 5, "Got Correct charfield for result object");
  }
}

ARRAYREF_OF_ARRAYREF_STYLE: {
  $art_rs->populate([
    [qw/artistid name/],
    [1000, 'A Formally Unknown Singer'],
    [1001, 'A singer that jumped the shark two albums ago'],
    [1002, 'An actually cool singer.'],
  ]);

  ok my $unknown = $art_rs->find(1000), "got Unknown";
  ok my $jumped = $art_rs->find(1001), "got Jumped";
  ok my $cool = $art_rs->find(1002), "got Cool";

  is $unknown->name, 'A Formally Unknown Singer', 'Correct Name';
  is $jumped->name, 'A singer that jumped the shark two albums ago', 'Correct Name';
  is $cool->name, 'An actually cool singer.', 'Correct Name';

  my ($cooler, $lamer) = $restricted_art_rs->populate([
    [qw/artistid name/],
    [1003, 'Cooler'],
    [1004, 'Lamer'],
  ]);

  is $cooler->name, 'Cooler', 'Correct Name';
  is $lamer->name, 'Lamer', 'Correct Name';

  for ($cooler, $lamer) {
    $_->discard_changes;
    cmp_ok( $_->rank, '==', 42, "Got Correct rank for result object");
    cmp_ok( $_->charfield, '==', $_->id + 5, "Got Correct charfield for result object");
  }

  ARRAY_CONTEXT_WITH_COND_FROM_RS: {

    my ($mega_lamer) = $restricted_art_rs->populate([
      {
        name => 'Mega Lamer',
      },
    ]);

    ## Did it use the condition in the resultset?
    $mega_lamer->discard_changes;
    cmp_ok( $mega_lamer->rank, '==', 42, "Got Correct rank for result object");
    cmp_ok( $mega_lamer->charfield, '==', $mega_lamer->id + 5, "Got Correct charfield for result object");
  }

  VOID_CONTEXT_WITH_COND_FROM_RS: {

    $restricted_art_rs->populate([
      {
        name => 'VOID Mega Lamer',
      },
    ]);

    my $mega_lamer = $art_rs->search({
      name => 'VOID Mega Lamer'
    })->first;

    ## Did it use the condition in the resultset?
    cmp_ok( $mega_lamer->rank, '==', 42, "Got Correct rank for result object");
    cmp_ok( $mega_lamer->charfield, '==', $mega_lamer->id + 5, "Got Correct charfield for result object");
  }
}

ok(eval { $art_rs->populate([]); 1 }, "Empty populate runs but does nothing");

done_testing;
