# $Id: 13_loop.t 1077 2008-09-01 19:02:06Z tinita $

use Test::More tests => 2;
BEGIN { use_ok('HTML::Template::Compiled') };
use lib 't';
use
HTC_Utils qw($cache $tdir &cdir);

{
	my $htc = HTML::Template::Compiled->new(
		scalarref => \<<'EOM',
<%set_var FOO value=.root.foo %>
<%= FOO %>
<%include var_include.html %>
EOM
		debug => 0,
        loop_context_vars => 1,
        path => $tdir,
	);
	$htc->param(
        root => {
            foo => 23,
        },
    );
	my $out = $htc->output;
	$out =~ s/\s+//g;
	cmp_ok($out, "eq", "2323", "set_var, use_vars");
	#print "out: $out\n";
}
