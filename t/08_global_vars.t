# Before `make install' is performed this script should be runnable with
# `make test'. After `make install' it should work as `perl HTML-Template-Compiled.t'
# $Id: 08_global_vars.t,v 1.2 2005/11/21 21:19:21 tinita Exp $

use lib 'blib/lib';
use Test::More tests => 2;
BEGIN { use_ok('HTML::Template::Compiled') };

my $htc = HTML::Template::Compiled->new(
	path => 't/templates',
	filehandle => \*DATA,
	global_vars => 1,
	#debug => 1,
);

$htc->param(
	global => 42,
	outer => [
		{
			loopvar => 'one',
		},
		{
			loopvar => 'two',
			global => 23,
		},
		{
			loopvar => 'three',
		},
	],
);
my $out = $htc->output;
#print $out;
ok($out =~ m/loopvar: one.*global: 42.*loopvar: two.*global: 23.*loopvar: three.*global: 42/s, 'global_vars');

__DATA__
global: <tmpl_var global>
<tmpl_loop outer>
 loopvar: <tmpl_var loopvar>
 global: <tmpl_var global>
</tmpl_loop>

