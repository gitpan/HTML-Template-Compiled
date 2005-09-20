# $Id: 05_filter.t,v 1.2 2005/09/19 22:43:02 tinita Exp $
use lib 'blib/lib';
use Test::More tests => 2;
BEGIN { use_ok('HTML::Template::Compiled') };

{
	# test filter
	my $htc = HTML::Template::Compiled->new(
		path => 't',
		filename => 'filter.htc',
		filter => [
			{
				'sub' => sub {
					for (${$_[0]}) {
						s#{{{ nomen est (\w+) }}}#<tmpl_var name="$1">#gi;
						s#{{{ iterate over (\w+) }}}#<tmpl_loop name="$1">#gi;
						s#{{{ end of iterate }}}#</tmpl_loop>#gi;
					};
				},
			},
		],
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
	ok($out eq $exp, "filter 1");
	#print "\n($out)\n($exp)\n";
}

__END__
Name: {{{ nomen est omen }}}
{{{ iterate over list }}}War: Bellum {{{ nomen est bellum }}
{{{ end of iterate }}}

