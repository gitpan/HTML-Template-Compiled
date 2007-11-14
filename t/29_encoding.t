# $Id: 29_encoding.t,v 1.4 2007/11/12 19:41:41 tinita Exp $
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
my $template = File::Spec->catfile(qw/ t templates utf8.htc /);
#use Devel::Peek;
SKIP: {
	skip "no URI::Escape, HTML::Entities and Encode installed", 1 unless $uri && $he && $encode;
    open my $fh, '>:utf8', $template;
    my $string = <<"EOM";
test utf8: \x{f6}
<%= utf8 escape=url %>
<%= utf8 escape=html_all %>
EOM
    print $fh $string;
    #Dump $string;
    close $fh;
    my $htc = HTML::Template::Compiled->new(
        filename => 'utf8.htc',
        path => $tdir,
        debug    => 0,
        open_mode => '<:utf8',
    );
    my $u = "ä";
    $u = Encode::decode_utf8($u);

    $htc->param(
        utf8 => $u,
    );
    my $out = $htc->output;
    #print "out: $out\n";
    #Dump $out;
    cmp_ok($out, '=~', qr{\x{f6}.*%C3%A4.*&auml;}is, "uri_escape_utf8");
    unlink $template;
}

