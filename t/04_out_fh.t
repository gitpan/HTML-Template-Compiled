# $Id: 04_out_fh.t,v 1.1 2005/09/19 20:56:06 tinita Exp $
use lib 'blib/lib';
use Test::More tests => 2;
BEGIN { use_ok('HTML::Template::Compiled') };

{
	# test output($fh)
	my $htc = HTML::Template::Compiled->new(
		path => 't',
		filename => 'out_fh.htc',
		out_fh => 1,
	);
	my $out = File::Spec->catfile('t', 'out_fh.htc.output');
	open my $fh, '>', $out or die $!;
	$htc->output($fh);
	close $fh;
	ok(-s $out == -s File::Spec->catfile('t', 'out_fh.htc'), "out_fh");
}
