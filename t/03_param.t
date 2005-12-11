# Before `make install' is performed this script should be runnable with
# `make test'. After `make install' it should work as `perl HTML-Template-Compiled.t'
# $Id: 03_param.t,v 1.5 2005/12/08 23:21:42 tinita Exp $

use lib 'blib/lib';
use Test::More tests => 5;
BEGIN { use_ok('HTML::Template::Compiled') };

my $htc = HTML::Template::Compiled->new(
	path => 't/templates',
	scalarref => \'<tmpl_var foo> <tmpl_var bar>',
);

$htc->param(
	this => {
		is => [qw(a test for param)],
		returning => 'the value for a parameter',
	},
);
my $test = $htc->param("this");
ok($test->{is}->[3] eq 'param', "param('var')");
my @param = sort $htc->param();
TODO: {
	local $TODO = "param() should behave like query and query is not implemented yet";
	cmp_ok(@param, "==", 2, "param() 1");
	cmp_ok($param[0], "eq", 'bar', "param() 2");
	cmp_ok($param[1], "eq", 'foo', "param() 2");
	#my @qyery = sort $htc->query();
	#cmp_ok("@param", "eq", "@query", "query");
}
