# $Id: 26_expr.t 1103 2009-08-23 13:10:31Z tinita $
use warnings;
use strict;
use lib 't';

# implement this later
use Test::More tests => 12;
eval { require Parse::RecDescent; };
my $prd = $@ ? 0 : 1;
use_ok('HTML::Template::Compiled');
use HTC_Utils qw($cache $tdir &cdir);

sub HT_Utils::list { my @a = qw/ a b c /; return @a }
sub HT_Utils::each { my %a = ( a => 1, b => 2 ); return %a }
SKIP: {
    skip "No Parse::RecDescent installed", 11 unless $prd;
    use_ok('HTML::Template::Compiled::Expr');
    my $htc;
    eval {
        $htc = HTML::Template::Compiled->new(
            scalarref => \<<'EOM',
            [%= expr="(foo.count < 4)  && ( foo.count > 2)" %]
EOM
            use_expressions => 0,
            tagstyle => [qw/ -classic -comment -asp +tt /],
            loop_context_vars => 1,
        );
    };
    my $error = $@;
    #warn __PACKAGE__.':'.__LINE__.": $@\n";
    cmp_ok($error, '=~', qr/\QSyntax error in <TMPL_*> tag/, "No expressions allowed");
    my @tests = (
        [ q#[%= expr="(foo.count < 4)  && ( foo.count > 2)" %]#, 1],
        [ q#[%= expr="(foo.count > 4)  && ( foo.count % 2)" %]#, ''],
        [ q#[%= expr="lcfirst( .string )" %]#, 'aBC'],
        [ q#[%if expr="lcfirst( .string ) eq 'aBC'" %]23[%/if %]#, '23'],
        [ q#[%if expr="'string\'' eq 'string\''" %]23[%/if %]#, '23'],
        [ q#[%= expr="object.param('foo', .foo.count )" %]#, '424242'],
        [ q#[%if expr="0" %]zero[%elsif expr="foo.count < 4" %]< 4[%/if %]#, '< 4'],
        [ q#[%loop expr="list_object.list" context="list" %][%= _ %][%/loop %]#, 'abc'],
        [ q#[%each expr="list_object.each" context="list" %]k:[%= __key__ %] [%/each %]#, 'k:a k:b '],
    );
    for my $i (0 .. $#tests) {
        my $test = $tests[$i];
        my ($tmpl, $exp) = @$test;
        my $htc = HTML::Template::Compiled->new(
            scalarref => \$tmpl,
            use_expressions => 1,
            debug => 0,
            tagstyle => [qw/ -classic -comment -asp +tt /],
            loop_context_vars => 1,
        );
        my $list_object = bless {}, 'HT_Utils';
        $htc->param(foo => {
                count => '3',
            },
            object => bless ({ foo => 42 }, 'HTC::DUMMY'),
            string => 'ABC',
            list_object => $list_object,
        );
        my $out = $htc->output;
        #print "out: $out\n";
        cmp_ok($out, 'eq', $exp, "Expressions $i");
    }
}

sub HTC::DUMMY::param {
    return $_[0]->{ $_[1] } x $_[2]
}
