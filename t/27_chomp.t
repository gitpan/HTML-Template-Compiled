# $Id: 27_chomp.t,v 1.1 2006/11/03 18:56:51 tinita Exp $
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
<tmpl_var foo  ~>
<tmpl_var  foo >
<~!-- tmpl_var foo  -->
<~%var foo %~>
EOM
        debug => 0,
    );
    $htc->param(foo => 23);
    my $out = $htc->output;
    #print "out: $out\n";
    cmp_ok($out, 'eq', '23232323', "chomp");
}


