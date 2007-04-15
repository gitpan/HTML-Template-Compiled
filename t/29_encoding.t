# $Id: 29_encoding.t,v 1.2 2007/04/15 12:53:50 tinita Exp $
use warnings;
use strict;
use blib;
use lib 't';
use Test::More tests => 2;
use_ok('HTML::Template::Compiled');
use HTC_Utils qw($cache $tdir &cdir);

eval { require URI::Escape };
my $uri = $@ ? 0 : 1;
eval { require Encode };
my $encode = $@ ? 0 : 1;
SKIP: {
	skip "no URI::Escape and Encode installed", 1 unless $uri && $encode;
    my $htc = HTML::Template::Compiled->new(
        filename => 'utf8.htc',
        path => $tdir,
        debug    => 0,
        cache_dir => $cache,
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


