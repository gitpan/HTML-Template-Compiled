# Before `make install' is performed this script should be runnable with
# `make test'. After `make install' it should work as `perl HTML-Template-Compiled.t'
# $Id: 15_comment.t,v 1.4 2006/01/06 13:35:10 tinita Exp $

use lib 'blib/lib';
use Test::More tests => 4;
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
<tmpl_elsif noparse>
	<tmpl_var wanted>
	<tmpl_noparse outer>
		<tmpl_noparse inner>
			<tmpl_var unwanted>
		</tmpl_noparse inner>
		<tmpl_var unwanted>
	</tmpl_noparse outer>
<tmpl_elsif escape>
    <tmpl_verbatim outer>
        this should be escaped: <tmpl_var test>
    </tmpl_verbatim outer>
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
		noparse => 1,
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
    my $unescaped = 'this should be escaped: <tmpl_var test>';
    eval { require HTML::Entities };
    SKIP: {
        skip "no HTML::Entities installed", 1, if $@;
        my $escaped = $unescaped;
        HTML::Entities::encode_entities($escaped);
        $htc->clear_params();
        $htc->param(
            escape => 1,
            wanted => "we want this",
            unwanted => "no thanks",
        );
        $out = $htc->output;
        #print $out,$/;
        like($out, qr/\Q$escaped/, "tmpl_verbatim");
    }
}
