# $Id: 27_chomp.t,v 1.2 2007/05/23 20:58:06 tinita Exp $
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
<+-tmpl_var foo  >
<tmpl_var  foo >
<-+!-- tmpl_var foo  -->
<--%var foo %>
EOM
        tagstyle => [qw(classic classic_chomp asp asp_chomp comment comment_chomp)],
        debug => 0,
    );
    $htc->param(foo => 23);
    my $out = $htc->output;
    #print "out: $out\n";
    cmp_ok($out, 'eq', '23232323', "chomp");
}


