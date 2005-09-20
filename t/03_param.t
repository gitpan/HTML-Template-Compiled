# Before `make install' is performed this script should be runnable with
# `make test'. After `make install' it should work as `perl HTML-Template-Compiled.t'
# $Id: 03_param.t,v 1.1 2005/09/19 20:59:43 tinita Exp $

use lib 'blib/lib';
use Test::More tests => 2;
BEGIN { use_ok('HTML::Template::Compiled') };
#$HTML::Template::Compiled::NEW_CHECK = 2;

my $htc = HTML::Template::Compiled->new(
	path => 't',
	filename => 'songs.html',
);

$htc->param(
	this => {
		is => [qw(a test for param)],
		returning => 'the value for a parameter',
	},
);
my $test = $htc->param("this");
ok($test->{is}->[3] eq 'param', "param('var')");
