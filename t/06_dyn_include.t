# Before `make install' is performed this script should be runnable with
# `make test'. After `make install' it should work as `perl HTML-Template-Compiled.t'
# $Id: 06_dyn_include.t,v 1.3 2005/11/21 21:19:21 tinita Exp $

use lib 'blib/lib';
use Test::More tests => 3;
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
	ok(
		$out =~ m/^Dynamic include:/m
			&& $out =~ m/^This is dynamically included file $ix\./m
			&& $out =~ m/^23/m,
		"dynamic include $ix",
	);
}


__END__
Dynamic include:
This is dynamically included file 1.
23
