package HTML::Template::Compiled::Plugin::DHTML;
# $Id: DHTML.pm,v 1.1.1.1 2005/09/10 16:52:29 tinita Exp $
use strict;
use warnings;
use vars '$VERSION';
$VERSION = "0.01";
use Data::TreeDumper;

sub dumper {
	my ($var) = @_;
	my $style;
	my $body = DumpTree($var, 'Data',
		DISPLAY_ROOT_ADDRESS => 1,
		DISPLAY_PERL_ADDRESS => 1,
		DISPLAY_PERL_SIZE => 1,
		RENDERER => {
			NAME => 'DHTML',
			STYLE => \$style,
			BUTTON => {
				COLLAPSE_EXPAND => 1,
				SEARCH => 1,
			}
		}
	);
	return $style.$body;
}

1;
