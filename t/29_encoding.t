# $Id: 29_encoding.t,v 1.3 2007/04/17 11:51:15 tinita Exp $
use warnings;
use strict;
use blib;
use lib 't';
use Test::More tests => 2;
use_ok('HTML::Template::Compiled');
use HTC_Utils qw($cache $tdir &cdir);

eval { require URI::Escape };
my $uri = $@ ? 0 : 1;
eval { require HTML::Entities };
my $he = $@ ? 0 : 1;
eval { require Encode };
my $encode = $@ ? 0 : 1;
SKIP: {
	skip "no URI::Escape, HTML::Entities and Encode installed", 1 unless $uri && $he && $encode;
    my $htc = HTML::Template::Compiled->new(
        filename => 'utf8.htc',
        path => $tdir,
        debug    => 0,
    );
    my $u = "ä";
    $u = Encode::decode_utf8($u);

    $htc->param(
        utf8 => $u,
    );
    my $out = $htc->output;
    #print "out: $out\n";
    cmp_ok($out, '=~', qr{%C3%A4.*&auml;}is, "uri_escape_utf8");

}


