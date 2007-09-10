# $Id: 32_compile_plugin.t,v 1.2 2007/08/13 12:30:10 tinita Exp $
use warnings;
use strict;
use blib;
use lib 't';
use Test::More tests => 1;
use HTML::Template::Compiled;
use HTC_Utils qw($cache $tdir &cdir);
use HTC_Plugin;

{
    my $htc = HTML::Template::Compiled->new(
        scalarref => \<<'EOM',
<%homer beer=beercount %>
<%bart donut=donutcount %>
EOM
        plugin => [qw(HTC_Plugin1 HTC_Plugin2)],
        debug    => 0,
    );
    $htc->param(
        beercount => 3,
        donutcount => 7,
    );

    my $out = $htc->output;
    #print "out: $out\n";
    cmp_ok($out, '=~', qr{Homer wants 3 beers.*Bart wants 7 donuts}s, "two plugins");
}


