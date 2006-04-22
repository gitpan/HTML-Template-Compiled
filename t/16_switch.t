# Before `make install' is performed this script should be runnable with
# `make test'. After `make install' it should work as `perl HTML-Template-Compiled.t'
# $Id: 16_switch.t,v 1.2 2006/04/21 22:45:42 tinita Exp $

use lib 'blib/lib';
use Test::More tests => 3;
use Data::Dumper;
use File::Spec;
use strict;
use warnings;
local $Data::Dumper::Indent = 1; local $Data::Dumper::Sortkeys = 1;
BEGIN { use_ok('HTML::Template::Compiled') };
$HTML::Template::Compiled::NEW_CHECK = 2;
my $cache = File::Spec->catfile('t', 'cache');

{
	my $htc = HTML::Template::Compiled->new(
		scalarref => \<<'EOM',
<tmpl_switch .lang>
    <tmpl_case en>
	english
	<tmpl_case de,fr>
		german or french
		<tmpl_switch lang>
		<tmpl_case de>german
		</tmpl_switch>
	<tmpl_case>
		default
</tmpl_switch>
<tmpl_switch .lang>
	<tmpl_case fr,default>
    french or default
</tmpl_switch>
EOM
		debug => 0,
	);
	$htc->param(
		lang => 'de',
	);
	my $out = $htc->output;
    #print $out,$/;
	ok($out =~ m/german or french.*german/s, "switch");
	ok($out =~ m/french or default/s, "switch default");
}
