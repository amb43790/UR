#!/usr/bin/env perl
use strict;
use warnings;
use File::Basename;
use lib File::Basename::dirname(__FILE__)."/../../../lib";
use lib File::Basename::dirname(__FILE__)."/../..";
use URT;
use Test::More tests => 2;

# A thing has many attributes, which are ordered and have names
UR::Object::Type->define(
    class_name => 'Thing',
    id_by => 'thing_id',
    has_many => [
        attribs => {
            is => 'Attribute',
            reverse_as => 'thing',
        },
        favorites => {
            via => 'attribs',
            where => [ key => 'favorite', '-order_by' => 'rank' ],
            to => 'value',
        },
    ],
    data_source => 'URT::DataSource::SomeSQLite',
    table_name => 'things',
);

UR::Object::Type->define(
    class_name => 'Attribute',
    id_by => 'attrib_id',
    has => [
        thing => { is => 'Thing', id_by => 'thing_id' },
        key => { is => 'String' },
        rank => { is => 'Integer' },
        value => { is => 'String' },
    ],
    data_source => 'URT::DataSource::SomeSQLite',
    table_name => 'attribs',
);

my $bx = Attribute->define_boolexpr(thing_id => 'foo', key => 'foo', -order_by => 'rank');
my $tmpl = $bx->template;
print "*** Constructed tmpl: ",Data::Dumper::Dumper($tmpl);

subtest 'in database' => sub {
    plan tests => 3;

    my $thing_id = 99;

    my $dbh = URT::DataSource::SomeSQLite->get_default_handle();
    ok($dbh->do('create table things (thing_id integer NOT NULL PRIMARY KEY)'),
        'create table things');
    ok($dbh->do('create table attribs (attrib_id integer NOT NULL PRIMARY KEY, thing_id INTEGER REFERENCES things(thing_id), key VARCHAR NOT NULL, rank INTEGER NOT NULL, value VARCHAR)'),
        'create table attributes');

    $dbh->do("insert into things values ($thing_id)");

    my $insert = $dbh->prepare('insert into attribs values (?,?,?,?,?)');
    foreach my $val ( [ 99,  $thing_id, 'favorite', 4, 4 ],
                      [ 100, $thing_id, 'favorite', 2, 2 ],
                      [ 101, $thing_id, 'favorite', 6, 6 ],
                      [ 102, $thing_id, 'favorite', 1, 1 ],
                      [ 103, $thing_id, 'name', 1, 'Fred' ],
    ) {
        $insert->execute(@$val);
    }

    my $thing = Thing->get($thing_id);
    my @favorites = $thing->favorites();
    is_deeply(
        \@favorites,
        [ 1, 2, 4, 6],
        'Got back ordered favorites');
};

subtest 'in-memory' => sub {
    plan tests => 1;

    my $thing = Thing->create();
    Attribute->create(thing_id => $thing->id, key => 'name', value => 'Bob', rank => 1);
    Attribute->create(thing_id => $thing->id, key => 'favorite', value => $_, rank => $_) foreach (qw( 4 2 6 1 ));

    my @favorites = $thing->favorites();
    is_deeply(
        \@favorites,
        [1, 2, 4, 6],
        'Got back ordered favorites');
};

