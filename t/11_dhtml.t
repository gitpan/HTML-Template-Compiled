# Before `make install' is performed this script should be runnable with
# `make test'. After `make install' it should work as `perl HTML-Template-Compiled.t'
# $Id: 11_dhtml.t,v 1.2 2005/11/21 21:19:21 tinita Exp $

use lib 'blib/lib';
use Test::More tests => 2;
BEGIN { use_ok('HTML::Template::Compiled') };

eval {
	require HTML::Template::Compiled::Plugin::DHTML;
   	require Data::TreeDumper::Renderer::DHTML;
};
my $dhtml = $@ ? 0 : 1;
SKIP: {
	my %hash = (
		dhtml => [
			qw(array items),
			[qw(inner array)],
		],
		more => {
			hash => 'keys',
		},
	);
	skip "no DHTML installed", 1 unless $dhtml;
	my $htc = HTML::Template::Compiled->new(
		filename => "t/templates/dhtml.htc",
		dumper => 'DHTML',
	);
	$htc->param(%hash);
	my $out = $htc->output;
	#print $out;
	ok($out =~ m/data_treedumper_dhtml/, 'DHTML plugin');
}

