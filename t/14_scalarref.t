# Before `make install' is performed this script should be runnable with
# `make test'. After `make install' it should work as `perl HTML-Template-Compiled.t'
# $Id: 14_scalarref.t,v 1.1 2005/12/05 21:43:17 tinita Exp $

use lib 'blib/lib';
use Test::More tests => 5;
use Data::Dumper;
use File::Spec;
use strict;
use warnings;
local $Data::Dumper::Indent = 1; local $Data::Dumper::Sortkeys = 1;
BEGIN { use_ok('HTML::Template::Compiled') };
$HTML::Template::Compiled::NEW_CHECK = 2;
my $cache = File::Spec->catfile('t', 'cache');

eval { require Digest::MD5 };
my $md5 = $@ ? 0 : 1;
my $hash = {
	URITEST => 'a b c & d',
};
SKIP: {
	skip "no Digest::MD5", 1 unless $md5;
	my $text = qq{<TMPL_VAR .URITEST ESCAPE=URL>\n};
	my $htc = HTML::Template::Compiled->new(
		scalarref => \$text,
		cache_dir => $cache,
	);
	ok($htc, "scalarref template");
	$htc->param(%$hash);
	my $out = $htc->output;
	ok($out eq 'a%20b%20c%20%26%20d'.$/, "scalarref output");
}
{
	my $text = [qq(<TMPL_VAR .URITEST),qq( ESCAPE=URL >\n)];
	my $htc = HTML::Template::Compiled->new(
		arrayref => $text,
		cache_dir => $cache,
	);
	ok($htc, "arrayref template");
	$htc->param(%$hash);
	my $out = $htc->output;
	ok($out eq 'a%20b%20c%20%26%20d'.$/, "arrayref output");
}

