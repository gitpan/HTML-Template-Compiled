# Before `make install' is performed this script should be runnable with
# `make test'. After `make install' it should work as `perl HTML-Template-Compiled.t'
# $Id: 15_comment.t,v 1.3 2005/12/07 01:36:24 tinita Exp $

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
<tmpl_if comment>
	<tmpl_var wanted>
	<tmpl_comment outer>
		<tmpl_comment inner>
			<tmpl_var unwanted>
		</tmpl_comment inner>
		<tmpl_var unwanted>
	</tmpl_comment outer>
<tmpl_else>
	<tmpl_var wanted>
	<tmpl_noparse outer>
		<tmpl_noparse inner>
			<tmpl_var unwanted>
		</tmpl_noparse inner>
		<tmpl_var unwanted>
	</tmpl_noparse outer>
</tmpl_if comment>
EOM
		debug => 0,
	);
	$htc->param(
		comment => 1,
		wanted => "we want this",
		unwanted => "no thanks",
	);
	my $out = $htc->output;
	#print $out,$/;
	ok(
		($out !~ m/unwanted/) &&
		$out !~ m/no thanks/ &&
		$out =~ m/we want this/,
		"tmpl_comment");
	$htc->clear_params();
	$htc->param(
		comment => 0,
		wanted => "we want this",
		unwanted => "no thanks",
	);
	$out = $htc->output;
	#print $out,$/;
	ok(
		((() = $out =~ m/unwanted/g) == 2) &&
		$out !~ m/no thanks/ &&
		$out =~ m/we want this/,
		"tmpl_noparse");
}
