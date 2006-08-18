package HTML::Template::Compiled::Expression;
# $Id: Expression.pm,v 1.2 2006/07/17 22:57:15 tinita Exp $
use strict;
use warnings;

use constant OPERANDS => 0;
use constant ATTRIBUTES => 1;
use base 'Exporter';
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
use HTML::Template::Compiled::Expression::Conditional;
use HTML::Template::Compiled::Expression::Function;

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
1;

__END__

=head1 NAME

HTML::Template::Compiled::Expression

=head1 DESCRIPTION

Superclass for all expression types.
