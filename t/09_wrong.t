# Before `make install' is performed this script should be runnable with
# `make test'. After `make install' it should work as `perl HTML-Template-Compiled.t'
# $Id: 09_wrong.t,v 1.6 2005/11/23 20:20:11 tinita Exp $

use lib 'blib/lib';
use Test::More tests => 5;
BEGIN { use_ok('HTML::Template::Compiled') };
eval {
	my $htc = HTML::Template::Compiled->new(
		scalarref => \<<'EOM',
		<tmpl_if foo>bar</tmpl_if>
		<%if foo %>bar<%/if%>
		<%if foo %>bar
EOM
		debug => $ENV{HARNESS_ACTIVE} ? 0 : 1,
		line_numbers => 1,
	);
};
print "err: $@\n" unless $ENV{HARNESS_ACTIVE};
ok($@ =~ m/Missing closing tag for 'IF'/, "premature end of template");
# test wrong balanced tag
my $wrong;
eval {
	$wrong = HTML::Template::Compiled->new(
		path => 't/templates',
		line_numbers => 1,
		filename => 'wrong.html',
		debug => $ENV{HARNESS_ACTIVE} ? 0 : 1,
	); 
};
print "err: $@\n" unless $ENV{HARNESS_ACTIVE};
ok($@ =~ m/does not match opening tag/ , "wrong template");

eval {
	my $htc = HTML::Template::Compiled->new(
		path => 't/templates',
		filename => 'notexist.htc',
		debug => $ENV{HARNESS_ACTIVE} ? 0 : 1,
	);
};
print "err: $@\n" unless $ENV{HARNESS_ACTIVE};
ok($@ =~ m/not found/ , "template not found");

eval {
	my $str = <<'EOM';
<tmpl_include name="notexist.htc">
EOM
	my $htc = HTML::Template::Compiled->new(
		path => 't/templates',
		scalarref => \$str,
		debug => $ENV{HARNESS_ACTIVE} ? 0 : 1,
	);
};
print "err: $@\n" unless $ENV{HARNESS_ACTIVE};
ok($@ =~ m/not found/ , "template from include not found");


