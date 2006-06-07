# $Id: 19_query.t,v 1.5 2006/04/27 20:14:05 tinita Exp $
use warnings;
use strict;
use lib 'blib/lib';
use Test::More tests => 3;

HTML::Template::Compiled->clear_filecache('t/cache');
# test query() (From HTML::Template test suite)
use HTML::Template::Compiled;
$HTML::Template::Compiled::NEW_CHECK = 1;
#$HTML::Template::Compiled::NEW_CHECK = 10000;
use File::Copy;
use Fcntl qw(:seek);
my $file_orig = File::Spec->catfile(qw(t templates query-test.tmpl));
my $file_copy = File::Spec->catfile(qw(t templates query-test-copy.tmpl));
copy($file_orig, $file_copy);
my $ok1 = query_template();
ok($ok1, "query 1");
#print `ls t/cache`;
{
    open my $fh, '+<', $file_copy or die $!;
    local $/;
    my $data = <$fh>;
    seek $fh, SEEK_SET, 0;
    truncate $fh, 0;
    $data =~ s/EXAMPLE_INNER_LOOP/EXAMPLE_INNER_LOOP_TEST/;
    print $fh $data;
    close $fh;
}
sleep 3;
my $ok2 = query_template();
ok(!$ok2, "query 2");

sub query_template {
    local $HTML::Template::Compiled::DEFAULT_QUERY = 1;
    my $template = HTML::Template::Compiled->new(
        path     => 't/templates',
        filename => 'query-test-copy.tmpl',
        cache_dir => 't/cache',
    );
    my %params;
    eval {
        %params = map {$_ => 1} $template->query(loop => 'EXAMPLE_LOOP');
    };

    my @result;
    eval {
        @result = $template->query(loop => ['EXAMPLE_LOOP', 'BEE']);
    };

    my $ok = (
    $@ =~ /error/ and
       $template->query(name => 'var') eq 'VAR' and
       $template->query(name => 'EXAMPLE_LOOP') eq 'LOOP' and
       exists $params{bee} and
       exists $params{bop} and
       exists $params{example_inner_loop} and
       $template->query(name => ['EXAMPLE_LOOP', 'EXAMPLE_INNER_LOOP']) eq 'LOOP'
    );
    my $out = $template->output;
    $template->clear_cache;
    return $ok;

    print "out: $out\n";
}

{
    local $HTML::Template::Compiled::DEFAULT_QUERY = 1;
    # test query() (From HTML::Template test suite)
    my $template = HTML::Template::Compiled->new(                                
        path     => 't/templates',
        filename => 'query-test2.tmpl',
    );
    my %p;
    eval { %p = map {$_ => 1} $template->query(loop => ['LOOP_FOO', 'LOOP_BAR']); };
    ok(exists $p{foo} and exists $p{bar} and exists $p{bash});
}
HTML::Template::Compiled->clear_filecache('t/cache');