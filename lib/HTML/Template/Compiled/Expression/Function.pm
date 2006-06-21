package HTML::Template::Compiled::Expression::Function;
# $Id: Function.pm,v 1.2 2006/06/20 20:45:34 tinita Exp $
use strict;
use warnings;
use base qw(HTML::Template::Compiled::Expression);

sub init {
    my ($self, @ops) = @_;
    $self->set_operands([@ops]);
}
sub to_string {
    my ($self, $level) = @_;
    my $indent = $self->level2indent($level);
    my ($function, @ops) = $self->get_operands;
    return "$indent$function( " .
        join(", ", map {
                $_->to_string($level)
        } @ops) . " )";
}

package HTML::Template::Compiled::Expression::Method;
# $Id: Function.pm,v 1.2 2006/06/20 20:45:34 tinita Exp $
use strict;
use warnings;
use base qw(HTML::Template::Compiled::Expression::Function);

sub to_string {
    my ($self, $level) = @_;
    my $indent = $self->level2indent($level);
    my ($function, $object, @args) = $self->get_operands;
    return $indent . $object->to_string($level) .
        "->$function( " .
        join(", ", map {
                $_->to_string($level)
        } @args) . " )";
}

1;

