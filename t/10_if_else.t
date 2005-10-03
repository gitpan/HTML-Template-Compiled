# $Id: 10_if_else.t,v 1.1 2005/10/03 00:54:02 tinita Exp $
use lib 'blib/lib';
use Test::More tests => 2;
BEGIN { use_ok('HTML::Template::Compiled') };

use File::Spec;
my $cache = File::Spec->catfile('t', 'cache');
HTML::Template::Compiled->clear_filecache($cache);

test();
sub test {
	my ($type, $clearcache) = @_;
	my $str = <<'EOM';
<tmpl_if defined undef>WRONG<tmpl_elsif undef>WRONG<tmpl_else>RIGHT</tmpl_if>
<tmpl_if defined zero>RIGHT<tmpl_elsif zero>WRONG<tmpl_else>RIGHT</tmpl_if>
<tmpl_if defined true>RIGHT<tmpl_elsif true>RIGHT<tmpl_else>WRONG</tmpl_if>
EOM
	my $htc = HTML::Template::Compiled->new(
		path => 't',
		scalarref => \$str,
		#debug => 1,
	);
	$htc->param(
		'undef' => undef,
		'zero' => 0,
		'true' => 'a true value',
	);
	my $out = $htc->output;
	#print $out;
	my @right = $out =~ m/RIGHT/g;
	my @wrong = $out =~ m/WRONG/g;
	ok(@right == 3 && @wrong == 0, "if defined");
}
