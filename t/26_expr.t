# $Id: 26_expr.t 1052 2008-06-16 20:35:12Z tinita $
use warnings;
use strict;
use lib 't';

# implement this later
use Test::More tests => 9;
eval { require Parse::RecDescent; };
my $prd = $@ ? 0 : 1;
use_ok('HTML::Template::Compiled');
use HTC_Utils qw($cache $tdir &cdir);

SKIP: {
    skip "No Parse::RecDescent installed", 8 unless $prd;
    use_ok('HTML::Template::Compiled::Expr');
    my $htc;
    eval {
        $htc = HTML::Template::Compiled->new(
            scalarref => \<<'EOM',
            <%= expr="(foo.count < 4)  && ( foo.count > 2)" %>
EOM
            use_expressions => 0,
        );
    };
    my $error = $@;
    #warn __PACKAGE__.':'.__LINE__.": $@\n";
    cmp_ok($error, '=~', qr/\QSyntax error in <TMPL_*> tag/, "No expressions allowed");
    my @tests = (
        [ q#<%= expr="(foo.count < 4)  && ( foo.count > 2)" %>#, 1],
        [ q#<%= expr="(foo.count > 4)  && ( foo.count % 2)" %>#, ''],
        [ q#<%= expr="lcfirst( .string )" %>#, 'aBC'],
        [ q#<%if expr="lcfirst( .string ) eq 'aBC'" %>23<%/if %>#, '23'],
        [ q#<%if expr="'string\'' eq 'string\''" %>23<%/if %>#, '23'],
        [ q#<%= expr="object.param('foo', .foo.count )" %>#, '424242'],
    );
    for my $i (0 .. $#tests) {
        my $test = $tests[$i];
        my ($tmpl, $exp) = @$test;
        my $htc = HTML::Template::Compiled->new(
            scalarref => \$tmpl,
            use_expressions => 1,
            debug => 0,
        );
        $htc->param(foo => {
                count => '3',
            },
            object => bless ({ foo => 42 }, 'HTC::DUMMY'),
            string => 'ABC',
        );
        my $out = $htc->output;
        #print "out: $out\n";
        cmp_ok($out, 'eq', $exp, "Expressions $i");
    }
}

sub HTC::DUMMY::param {
    return $_[0]->{ $_[1] } x $_[2]
}
