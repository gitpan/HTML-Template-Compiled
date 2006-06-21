package HTML::Template::Compiled::Expression;
# $Id: Expression.pm,v 1.1 2006/06/15 21:59:37 tinita Exp $
use strict;
use warnings;

use constant OPERANDS => 0;
use constant ATTRIBUTES => 1;

sub new {
    my $class = shift;
    my $self = [ [], {} ];
    bless $self, $class;
    $self->init(@_);
    return $self;
}

sub init {}

sub set_operands {
    $_[0]->[OPERANDS] = $_[1];
}

sub get_operands {
    return wantarray
        ? @{ $_[0]->[OPERANDS] }
        : $_[0]->[OPERANDS];
}

sub set_attributes {
    $_[0]->[ATTRIBUTES] = $_[1];
}

sub get_attributes { return $_[0]->[ATTRIBUTES] }

sub to_string { print "$_[0] to_string\n" }

sub level2indent {
    my ($self, $level) = @_;
    return "  " x $level;
}

1;

__END__

=head1 NAME

HTML::Template::Compiled::Expression

=head1 DESCRIPTION

Superclass for all expression types.
