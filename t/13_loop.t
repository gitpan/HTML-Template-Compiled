# Before `make install' is performed this script should be runnable with
# `make test'. After `make install' it should work as `perl HTML-Template-Compiled.t'
# $Id: 13_loop.t,v 1.7 2007/03/01 22:54:39 tinita Exp $

use lib 'blib/lib';
use Test::More tests => 5;
BEGIN { use_ok('HTML::Template::Compiled') };

{
	my $htc = HTML::Template::Compiled->new(
		scalarref => \<<'EOM',
<tmpl_loop array alias=iterator>
<tmpl_var iterator>
</tmpl_loop>
EOM
		debug => 0,
        loop_context_vars => 1,
	);
	$htc->param(array => [qw(a b c)]);
	my $out = $htc->output;
	$out =~ s/\s+//g;
	cmp_ok($out, "eq", "abc", "tmpl_loop array alias=iterator");
	#print "out: $out\n";
}
my $text1 = <<'EOM';
<tmpl_loop array>
<tmpl_var __counter__>
<tmpl_var _.x>
</tmpl_loop>
EOM
for (0,1) {
	my $htc = HTML::Template::Compiled->new(
		scalarref => \$text1,
        debug => 0,
        loop_context_vars => $_,
	);
	$htc->param(array => [
        {x=>"a","__counter__"=>"A"},
        {x=>"b","__counter__"=>"B"},
        {x=>"c","__counter__"=>"C"},
    ]);
	my $out = $htc->output;
	$out =~ s/\s+//g;
	my $exp;
	if ($_ == 1) {
		$exp = "1a2b3c";
	}
	else {
		$exp = "AaBbCc";
	}
	#print "($out)($exp)\n";
	cmp_ok($out, "eq", $exp, "loop context");
}

{
    my $htc = HTML::Template::Compiled->new(
        scalarref => \<<EOM,
<%loop list join=", " %><%= _ %><%/loop list %>
EOM
    );
    $htc->param(
        list => [qw(a b c)]
    );
    my $out = $htc->output;
    $out =~ s/^\s+//;
    $out =~ s/\s+\z//;
    #print $out, $/;
    cmp_ok($out, 'eq','a, b, c', "loop join attribute");
}
