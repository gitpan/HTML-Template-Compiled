# $Id: 05_filter.t,v 1.5 2005/11/21 21:19:21 tinita Exp $
use lib 'blib/lib';
use Test::More tests => 4;
BEGIN { use_ok('HTML::Template::Compiled') };

my $filter = sub {
	for (${$_[0]}) {
		s#{{{ nomen est (\w+) }}}#<tmpl_var name="$1">#gi;
		s#{{{ iterate over (\w+) }}}#<tmpl_loop name="$1">#gi;
		s#{{{ end of iterate }}}#</tmpl_loop>#gi;
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
	my $htc = HTML::Template::Compiled->new(
		path => 't/templates',
		filename => 'filter.htc',
		filter => $f,
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

EOM
	my $out = $htc->output();
	ok($out eq $exp, "filter $i");
	$htc->clear_cache();
	#print "\n($out)\n($exp)\n";
}

__END__
Name: {{{ nomen est omen }}}
{{{ iterate over list }}}War: Bellum {{{ nomen est bellum }}
{{{ end of iterate }}}

