# $Id: 18_objects.t 1015 2008-03-01 01:19:09Z tinita $

use lib 'blib/lib';
use Test::More tests => 4;
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

for my $strict (qw/ strict nostrict/) {
	my $htc = HTML::Template::Compiled->new(
		scalarref => \<<'EOM',
        <%= object.get_content %>
        <%= object.dummy %>
EOM
		debug => 0,
        global_vars => 1,
        objects => $strict,
        cache => 0,
	);
    my $object = bless {
        content => 23,
    }, "HTC_Dummy";
	$htc->param(
        object => $object,
	);
    my $out = '';
    eval {
        $out = $htc->output;
    };
    #warn __PACKAGE__.':'.__LINE__.": error: $@\n";
	$out =~ s/\s+//g;
    #print $out,$/;
    if ($strict eq 'strict') {
        cmp_ok($@, "=~", q/Can't locate object method "dummy"/ , "global objects '$strict'");
    }
    else {
        cmp_ok($out, "eq", 23, "global objects '$strict'");
    }
}

sub HTC_Dummy::get_content {
    return $_[0]->{content};
}
