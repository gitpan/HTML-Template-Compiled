# Before `make install' is performed this script should be runnable with
# `make test'. After `make install' it should work as `perl HTML-Template-Compiled.t'
# $Id: 13_loop.t,v 1.3 2005/12/11 22:16:21 tinita Exp $

use lib 'blib/lib';
use Test::More tests => 4;
BEGIN { use_ok('HTML::Template::Compiled') };

{
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
	$out =~ s/\s+//g;
	cmp_ok($out, "eq", "abc", "tmpl_loop array as iterator");
	#print "out: $out\n";
}

my $text1 = <<'EOM';
<tmpl_loop array>
<tmpl_var __counter__>
<tmpl_var _>
</tmpl_loop>
EOM
my $text2 = <<'EOM';
<tmpl_loop array><tmpl_loop_context>
<tmpl_var __counter__>
<tmpl_var _>
</tmpl_loop>
EOM
for ($text1, $text2) {
	my $htc = HTML::Template::Compiled->new(
		scalarref => \$_,
	);
	$htc->param(array => [qw(a b c)]);
	my $out = $htc->output;
	$out =~ s/\s+//g;
	my $exp;
	if (m/<tmpl_loop_context>/) {
		$exp = "1a2b3c";
	}
	else {
		$exp = "abc";
	}
	#print "($out)($exp)\n";
	cmp_ok($out, "eq", $exp, "loop context");
}
