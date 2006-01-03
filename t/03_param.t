# $Id: 03_param.t,v 1.9 2006/01/02 21:28:40 tinita Exp $

use lib 'blib/lib';
use Test::More tests => 8;
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


TODO: {
    my @param = sort $htc->param();
	local $TODO = "param() should behave like query and query is not implemented yet";
    print "(@param)\n";
	cmp_ok(@param, "==", 2, "param() 1");
	cmp_ok($param[0], "eq", 'bar', "param() 2");
	cmp_ok($param[1], "eq", 'foo', "param() 2");
	eval {
        my @query = sort $htc->query();
	    cmp_ok("@param", "eq", "@query", "query");
    };
}

param_accumulates: {
    $htc->clear_params;
    $htc->param({ foo => 'FOO VALUE' });
    like($htc->output, qr/FOO VALUE/);
    $htc->param({ bar => 'BAR VALUE' });
    like($htc->output, qr/FOO VALUE/);
}

literal_dot_is_ok: {
    # To be compatible with H::T, we need
    # to first check if a dot is literal
    # part of the name before treating it magically. 
    # This is important for a smooth upgrade path. 
    my $htc = HTML::Template::Compiled->new(
        path => 't/templates',
        scalarref => \'<tmpl_var foo.bar>',
    );
    $htc->param('foo.bar', 'WORKS');
    like($htc->output, qr/WORKS/, "literal dot is OK");
}


