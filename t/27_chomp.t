# $Id: 27_chomp.t,v 1.3 2007/10/09 18:24:59 tinita Exp $
use warnings;
use strict;
use blib;
use lib 't';
use Test::More tests => 3;
use_ok('HTML::Template::Compiled');
use HTC_Utils qw($cache $tdir &cdir);

{
    my $htc = HTML::Template::Compiled->new(
        scalarref => \<<'EOM',
<+-tmpl_var foo  >
<tmpl_var  foo >
<-+!-- tmpl_var foo  -->
<--%var foo %>
EOM
        tagstyle => [qw(+classic +classic_chomp +asp +asp_chomp +comment +comment_chomp)],
        debug => 0,
    );
    $htc->param(foo => 23);
    my $out = $htc->output;
    #print "out: $out\n";
    cmp_ok($out, 'eq', '23232323', "chomp");
}

{
    my $htc = HTML::Template::Compiled->new(
        scalarref => \<<'EOM',
<%loop foo %>
* <%= _ %>
<--%/loop %>

EOM
        tagstyle => [qw(+asp_chomp)],
        debug => 0,
    );
    my $exp = <<'EOM';

* 2
* 3
* 4
EOM
    $htc->param(foo => [2..4]);
    my $out = $htc->output;
    #print "out: $out\n";
    cmp_ok($out, 'eq', $exp, "chomp loop");
}


