# Before `make install' is performed this script should be runnable with
# `make test'. After `make install' it should work as `perl HTML-Template-Compiled.t'
# $Id: 17_escape.t,v 1.2 2005/12/22 22:40:54 tinita Exp $

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

eval { require HTML::Entities };
my $entities = $@ ? 0 : 1;

SKIP: {
	skip "no HTML::Entities installed", 3, unless $entities;
	
	my $htc = HTML::Template::Compiled->new(
		scalarref => \<<'EOM',
<tmpl_var html>
<tmpl_var nohtml ESCAPE=0>
EOM
		default_escape => 'HTML',
		debug => 0,
	);
	my $html = '<html>';
	my $nohtml = $html;
	$htc->param(
		html => $html,
		nohtml => $nohtml,
	);
	HTML::Entities::encode_entities($html);
	my $out = $htc->output;
	$out =~ tr/\n\r //d;
	#print $out,$/;
	cmp_ok($out, "eq", $html.$nohtml, "default_escape");
}
