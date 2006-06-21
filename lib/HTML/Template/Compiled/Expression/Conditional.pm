package HTML::Template::Compiled::Expression::Conditional;
# $Id: Conditional.pm,v 1.2 2006/06/20 21:12:24 tinita Exp $
use strict;
use warnings;
use base qw(HTML::Template::Compiled::Expression);

sub init {
    my ($self, $op) = @_;
    $self->set_operands([$op]);
}

package HTML::Template::Compiled::Expression::If;
use strict;
use warnings;
use base qw(HTML::Template::Compiled::Expression::Conditional);

sub to_string {
    my ($self, $level) = @_;
    my $indent = $self->level2indent($level);
    my ($op) = $self->get_operands;
    return $indent . 'if ( ' . $op->to_string . ' ) {';
}

package HTML::Template::Compiled::Expression::Unless;
use strict;
use warnings;
use base qw(HTML::Template::Compiled::Expression::Conditional);

sub to_string {
    my ($self, $level) = @_;
    my $indent = $self->level2indent($level);
    my ($op) = $self->get_operands;
    return $indent . 'unless ( ' . $op->to_string . ' ) {';
}

package HTML::Template::Compiled::Expression::Elsif;
use strict;
use warnings;
use base qw(HTML::Template::Compiled::Expression::Conditional);

sub to_string {
    my ($self, $level) = @_;
    my $indent = $self->level2indent($level);
    my ($op) = $self->get_operands;
    return $indent . '}' . $/ . $indent . 'elsif ( ' . $op->to_string . ' ) {';
}

package HTML::Template::Compiled::Expression::Else;
use strict;
use warnings;
use base qw(HTML::Template::Compiled::Expression::Conditional);

sub to_string {
    my ($self, $level) = @_;
    my $indent = $self->level2indent($level);
    return $indent . '}' . $/ . $indent . 'else {';
}


1;

