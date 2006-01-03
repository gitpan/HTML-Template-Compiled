# $Id: 18_objects.t,v 1.1 2006/01/02 21:32:43 tinita Exp $

use lib 'blib/lib';
use Test::More tests => 2;
use strict;
use warnings;
local $Data::Dumper::Indent = 1; local $Data::Dumper::Sortkeys = 1;
BEGIN { use_ok('HTML::Template::Compiled') };
my $cache = File::Spec->catfile('t', 'cache');

{
	my $htc = HTML::Template::Compiled->new(
		scalarref => \<<'EOM',
<tmpl_var outer.get_content>
<tmpl_with outer>
    <tmpl_var get_content>
</tmpl_with>
<tmpl_with foo>
    <tmpl_var inner.get_content>
    <tmpl_var outer.get_content>
</tmpl_with>
EOM
		debug => 0,
        global_vars => 1,
	);
    my $object = bless {
        content => 23,
    }, "HTC_Dummy";
	$htc->param(
        outer => $object,
        foo => {
            inner => $object,
        },
	);
	my $out = $htc->output;
	$out =~ tr/\n\r //d;
    #print $out,$/;
    cmp_ok($out, "eq", 23 x 4, "global objects");
}

sub HTC_Dummy::get_content {
    return $_[0]->{content};
}
