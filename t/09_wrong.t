# Before `make install' is performed this script should be runnable with
# `make test'. After `make install' it should work as `perl HTML-Template-Compiled.t'
# $Id: 09_wrong.t,v 1.4 2005/10/03 15:24:53 tinita Exp $

use lib 'blib/lib';
use Test::More tests => 4;
BEGIN { use_ok('HTML::Template::Compiled') };

# test wrong balanced tag
my $wrong;
eval {
	$wrong = HTML::Template::Compiled->new(
		path => 't',
		line_numbers => 1,
		filename => 'wrong.html',
		debug => $ENV{HARNESS_ACTIVE} ? 0 : 1,
	); 
};
print "err: $@\n" unless $ENV{HARNESS_ACTIVE};
ok($@ =~ m/does not match opening tag/ , "wrong template");

eval {
	my $htc = HTML::Template::Compiled->new(
		path => 't',
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
		path => 't',
		scalarref => \$str,
		debug => $ENV{HARNESS_ACTIVE} ? 0 : 1,
	);
};
print "err: $@\n" unless $ENV{HARNESS_ACTIVE};
ok($@ =~ m/not found/ , "template from include not found");
