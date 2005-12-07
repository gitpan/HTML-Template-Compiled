# Before `make install' is performed this script should be runnable with
# `make test'. After `make install' it should work as `perl HTML-Template-Compiled.t'
# $Id: 15_comment.t,v 1.1 2005/12/05 22:53:57 tinita Exp $

use lib 'blib/lib';
use Test::More tests => 2;
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
<tmpl_var wanted>
<tmpl_comment outer>
	<tmpl_comment inner>
		<tmpl_var unwanted>
	</tmpl_comment inner>
	<tmpl_var unwanted>
</tmpl_comment outer>
EOM
		debug => 0,
	);
	$htc->param(
		wanted => "we want this",
		unwanted => "no thanks",
	);
	my $out = $htc->output;
	#print $out,$/;
	ok(
		(() = $out =~ m/unwanted/g == 2) &&
		$out !~ m/no thanks/,
		"tmpl_comment");
}
