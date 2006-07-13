# $Id: 05_filter.t,v 1.6 2006/07/13 13:53:31 tinita Exp $
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
    utime(time, time, 't/templates/filter.htc') or die $!;
    utime(time, time, 't/templates/filter_included.htc');
    sleep 1;
	my $htc = HTML::Template::Compiled->new(
		path => 't/templates',
		filename => 'filter.htc',
		filter => $f,
        cache_dir => 't/cache',
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
	ok($out eq $exp, "filter $i");
	$htc->clear_cache();
    #print "\n($out)\n($exp)\n";
}

__END__
