# $Id: 03_param.t 429 2006-07-02 17:32:45Z tinita $

use lib 'blib/lib';
use Test::More tests => 11;
BEGIN {
    use_ok('HTML::Template::Compiled');
    use_ok('HTML::Template::Compiled::Classic');
}

{
local $HTML::Template::Compiled::DEFAULT_QUERY = 1;
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
    #print "(@param)\n";
	cmp_ok(@param, "==", 2, "param() 1");
	cmp_ok($param[0], "eq", 'bar', "param() 2");
	cmp_ok($param[1]||'', "eq", 'foo', "param() 2");
	eval {
        my @query = sort $htc->query();
	    cmp_ok("@param", "eq", "@query", "query");
    };

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
    my $htc = HTML::Template::Compiled::Classic->new(
        path => 't/templates',
        scalarref => \'<tmpl_var foo.bar>',
    );
    $htc->param('foo.bar', 'WORKS');
    like($htc->output, qr/WORKS/, "literal dot is OK");
}

subref_variables: {
    my $htc = HTML::Template::Compiled::Classic->new(
        scalarref => \"<TMPL_VAR foo><TMPL_LOOP loop><TMPL_VAR a><TMPL_VAR foo></TMPL_LOOP>",
        global_vars => 1,
    );
    $htc->param(
        foo => sub { return "bar" },
        loop => [{a=>23}],
    );
    my $out = $htc->output;
    #print "($out)\n";
    cmp_ok($out, 'eq', "bar23bar", "subref variables");
}


}

