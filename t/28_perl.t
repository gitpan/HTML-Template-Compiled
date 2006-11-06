# $Id: 28_perl.t,v 1.1 2006/11/06 22:13:33 tinita Exp $
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
[%perl __OUT__ "template: __HTC__";
my $test = __ROOT__->{foo};
__OUT__ $test;
%]
[%loop loop%]
[%perl __OUT__ __INDEX__ . ": " . __CURRENT__->{a}; %]
[%/loop loop%]

EOM
        use_perl => 1,
        debug    => 0,
        tagstyle => [qw(-classic -comment -asp +tt)],
    );
    $htc->param(
        foo => 23,
        loop => [{ a => 'A' },{ a => 'B' }],
    );
    my $out = $htc->output;
    #print "out: $out\n";
    cmp_ok($out, '=~',
        qr{template: HTML::Template::Compiled.*23.*0: A.*1: B}s, "perl-tag");
}


