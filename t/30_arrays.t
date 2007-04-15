# $Id: 30_arrays.t,v 1.2 2007/04/15 14:22:15 tinita Exp $
use warnings;
use strict;
use blib;
use lib 't';
use Test::More tests => 2;
use_ok('HTML::Template::Compiled');
use HTC_Utils qw($cache $tdir &cdir);

{
    my $htc = HTML::Template::Compiled->new(
        scalarref => \<<'EOM',
test <%= .array[0][0] %>
Count outer:   <%= .array# %>
Count inner 1: <%= .array[0]# %>
Count inner 2: <%= .array[1]# %>
EOM
        debug    => 0,
    );

    $htc->param(
        array => [
            [qw(a b c)],
            [qw(d e f g)],
        ],
    );
    my $out = $htc->output;
    print "out: $out\n";
    cmp_ok($out, '=~', "Count outer: +2", "array count");

}


