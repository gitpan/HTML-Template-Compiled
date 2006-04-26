# $Id: 19_query.t,v 1.4 2006/04/26 21:21:15 tinita Exp $
use warnings;
use strict;
use lib 'blib/lib';
use Test::More tests => 2;

# test query() (From HTML::Template test suite)
use HTML::Template::Compiled;
local $HTML::Template::Compiled::DEFAULT_QUERY = 1;
my $template = HTML::Template::Compiled->new(
    path     => 't/templates',
    filename => 'query-test.tmpl',
);
my %params;
eval {
    %params = map {$_ => 1} $template->query(loop => 'EXAMPLE_LOOP');
};

my @result;
eval {
    @result = $template->query(loop => ['EXAMPLE_LOOP', 'BEE']);
};

ok($@ =~ /error/ and
   $template->query(name => 'var') eq 'VAR' and
   $template->query(name => 'EXAMPLE_LOOP') eq 'LOOP' and
   exists $params{bee} and
   exists $params{bop} and
   exists $params{example_inner_loop} and
   $template->query(name => ['EXAMPLE_LOOP', 'EXAMPLE_INNER_LOOP']) eq 'LOOP'
);   

# test query() (From HTML::Template test suite)
$template = HTML::Template::Compiled->new(                                
    path     => 't/templates',
    filename => 'query-test2.tmpl',
);
my %p;
eval { %p = map {$_ => 1} $template->query(loop => ['LOOP_FOO', 'LOOP_BAR']); };
ok(exists $p{foo} and exists $p{bar} and exists $p{bash});

