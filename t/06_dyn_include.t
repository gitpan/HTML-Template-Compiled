# Before `make install' is performed this script should be runnable with
# `make test'. After `make install' it should work as `perl HTML-Template-Compiled.t'
# $Id: 06_dyn_include.t,v 1.4 2006/04/22 16:29:53 tinita Exp $

use lib 'blib/lib';
use Test::More tests => 7;
BEGIN { use_ok('HTML::Template::Compiled') };
#$HTML::Template::Compiled::NEW_CHECK = 2;

my $htc = HTML::Template::Compiled->new(
	path => 't/templates',
	filename => 'dyn_include.htc',
	debug => 0,
);

for my $ix (1..2) {
	$htc->param(
		file => "dyn_included$ix.htc",
		test => 23,
	);
	my $out = $htc->output;
    #print $out;
	$out =~ s/\r\n|\r/\n/g;
    cmp_ok($out, "=~",
        "Dynamic include:", "dynamic include $ix.1");
    cmp_ok($out, "=~", "This is dynamically included file $ix\.", "dynamic include $ix.2");
    cmp_ok($out, "=~", "23", "dynamic include $ix.3");
}


__END__
Dynamic include:
This is dynamically included file 1.
23
