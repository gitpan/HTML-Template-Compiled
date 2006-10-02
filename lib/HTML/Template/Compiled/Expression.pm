package HTML::Template::Compiled::Expression;
# $Id: Expression.pm,v 1.5 2006/10/02 15:48:02 tinita Exp $
use strict;
use warnings;

use constant OPERANDS => 0;
use constant ATTRIBUTES => 1;
use base 'Exporter';
our $VERSION = 0.02;
use  HTML::Template::Compiled::Expression::Expressions;
my @expressions = qw(
    &_expr_close
    &_expr_open
    &_expr_else
    &_expr_literal
    &_expr_defined
    &_expr_ternary
    &_expr_string
    &_expr_function
    &_expr_method
    &_expr_elsif
);
our @EXPORT_OK = @expressions;
our %EXPORT_TAGS = (
    expressions => \@expressions,
);

sub _expr_close { HTML::Template::Compiled::Expression::Close->new }
sub _expr_open { HTML::Template::Compiled::Expression::Open->new }
sub _expr_else { HTML::Template::Compiled::Expression::Else->new }
sub _expr_literal { HTML::Template::Compiled::Expression::Literal->new(@_) }
sub _expr_defined { HTML::Template::Compiled::Expression::Defined->new(@_) }
sub _expr_ternary { HTML::Template::Compiled::Expression::Ternary->new(@_) }
sub _expr_string { HTML::Template::Compiled::Expression::String->new(@_) }
sub _expr_function { HTML::Template::Compiled::Expression::Function->new(@_) }
sub _expr_method { HTML::Template::Compiled::Expression::Method->new(@_) }
sub _expr_elsif { HTML::Template::Compiled::Expression::Elsif->new(@_) }


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


package HTML::Template::Compiled::Expression::Conditional;
use base qw(HTML::Template::Compiled::Expression);

sub init {
    my ($self, $op) = @_;
    $self->set_operands([$op]);
}

package HTML::Template::Compiled::Expression::If;
our @ISA = qw(HTML::Template::Compiled::Expression::Conditional);

sub to_string {
    my ($self, $level) = @_;
    my $indent = $self->level2indent($level);
    my ($op) = $self->get_operands;
    return $indent . 'if ( ' . $op->to_string . ' ) {';
}

package HTML::Template::Compiled::Expression::Unless;
our @ISA = qw(HTML::Template::Compiled::Expression::Conditional);

sub to_string {
    my ($self, $level) = @_;
    my $indent = $self->level2indent($level);
    my ($op) = $self->get_operands;
    return $indent . 'unless ( ' . $op->to_string . ' ) {';
}

package HTML::Template::Compiled::Expression::Elsif;
our @ISA = qw(HTML::Template::Compiled::Expression::Conditional);

sub to_string {
    my ($self, $level) = @_;
    my $indent = $self->level2indent($level);
    my ($op) = $self->get_operands;
    return $indent . '}' . $/ . $indent . 'elsif ( ' . $op->to_string . ' ) {';
}

package HTML::Template::Compiled::Expression::Else;
our @ISA = qw(HTML::Template::Compiled::Expression::Conditional);

sub to_string {
    my ($self, $level) = @_;
    my $indent = $self->level2indent($level);
    return $indent . '}' . $/ . $indent . 'else {';
}

package HTML::Template::Compiled::Expression::Function;
our @ISA = qw(HTML::Template::Compiled::Expression);

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
our @ISA = qw(HTML::Template::Compiled::Expression::Function);

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


__END__

=head1 NAME

HTML::Template::Compiled::Expression

=head1 DESCRIPTION

Superclass for all expression types.
