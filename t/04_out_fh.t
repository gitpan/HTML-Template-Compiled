# $Id: 04_out_fh.t,v 1.5 2005/11/21 21:19:21 tinita Exp $
use lib 'blib/lib';
use Test::More tests => 5;
BEGIN { use_ok('HTML::Template::Compiled') };

use File::Spec;
my $cache = File::Spec->catfile('t', 'cache');
HTML::Template::Compiled->clear_filecache($cache);
test('compile', 'clearcache');
test('filecache');
test('memcache', 'clearcache');
HTML::Template::Compiled->preload($cache);
test('after preload', 'clearcache');

sub test {
	my ($type, $clearcache) = @_;
	# test output($fh)
	my $htc = HTML::Template::Compiled->new(
		path => 't/templates',
		filename => 'out_fh.htc',
		out_fh => 1,
		cache_dir => 't/cache',
	);
	my $out = File::Spec->catfile('t', 'templates', 'out_fh.htc.output');
	open my $fh, '>', $out or die $!;
	$htc->output($fh);
	close $fh;
	open my $f, '<', File::Spec->catfile('t', 'templates', 'out_fh.htc') or die $!;
	open my $t, '<', File::Spec->catfile('t', 'templates', 'out_fh.htc.output') or die $!;
	local $/;
	my $orig = <$f>;
	my $test = <$t>;
	for ($orig, $test) {
		tr/\n\r//d;
	}
	ok($orig eq $test, "out_fh $type");
	$htc->clear_cache() if $clearcache;

	# this is not portable
	#ok(-s $out == -s File::Spec->catfile('t', 'out_fh.htc'), "out_fh");
}