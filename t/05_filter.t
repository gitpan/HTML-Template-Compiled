# $Id: 05_filter.t,v 1.9 2007/11/04 21:00:19 tinita Exp $
use lib 'blib/lib';
use Test::More tests => 4;
BEGIN { use_ok('HTML::Template::Compiled') };
HTML::Template::Compiled->ExpireTime(1);

my $filter = sub {
	for (${$_[0]}) {
		s#{{{ nomen est (\w+) }}}#<tmpl_var name="$1">#gi;
		s#{{{ iterate over (\w+) }}}#<tmpl_loop name="$1">#gi;
		s#{{{ end of iterate }}}#</tmpl_loop>#gi;
		s#{{{ occupy (\S+) }}}#<tmpl_include $1>#gi;
	};
};
my $filters = {
	'sub' => $filter,
};
test($filter, 1);
test([$filters], 2);
test($filters, 3);

sub test {
	my ($f, $i) = @_;
	# test filter
    my $f1 = File::Spec->catfile(qw/ t templates filter.htc /);
    my $f2 = File::Spec->catfile(qw/ t templates filter_included.htc /);
    chmod 0644, $f1;
    chmod 0644, $f2;
    utime(time, time, $f1) or die $!;
    utime(time, time, $f2) or die $!;
    sleep 1;
	my $htc = HTML::Template::Compiled->new(
		path => 't/templates',
		filename => 'filter.htc',
		filter => $f,
        file_cache_dir => 't/cache',
        file_cache => 1,
	);
	$htc->param(
		omen => 'Caesar',
		list => [
			{ bellum => 'Gallicum' },
			{ bellum => 'Gallicum I' },
			{ bellum => 'Gallicum II' },
		],
	);
	my $exp = <<'EOM';
Name: Caesar
War: Bellum Gallicum
War: Bellum Gallicum I
War: Bellum Gallicum II

Included Name: Caesar

EOM
	my $out = $htc->output();
	cmp_ok($out, 'eq', $exp, "filter $i");
	$htc->clear_cache();
    #print "\n($out)\n($exp)\n";
}

__END__
