# Before `make install' is performed this script should be runnable with
# `make test'. After `make install' it should work as `perl HTML-Template-Compiled.t'
# $Id: 13_loop.t,v 1.2 2005/12/05 21:47:46 tinita Exp $

use lib 'blib/lib';
use Test::More tests => 2;
BEGIN { use_ok('HTML::Template::Compiled') };

my $htc = HTML::Template::Compiled->new(
	scalarref => \<<'EOM',
<tmpl_loop array as iterator>
<tmpl_var iterator>
</tmpl_loop>
EOM
	#debug => 1,
);
$htc->param(array => [qw(a b c)]);
my $out = $htc->output;
ok($out =~ m/a\s+b\s+c/, "tmpl_loop array as iterator");
#print "out: $out\n";
