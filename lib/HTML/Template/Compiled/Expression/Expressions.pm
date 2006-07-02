package HTML::Template::Compiled::Expression::Expressions;
# $Id: Expressions.pm,v 1.5 2006/07/02 14:08:10 tinita Exp $
use strict;
use warnings;
use base 'Exporter';
our @EXPORT = qw(
    &_expr_close
    &_expr_else
    &_expr_literal
    &_expr_defined
    &_expr_ternary
    &_expr_string
    &_expr_function
    &_expr_method
);
use HTML::Template::Compiled::Expression::Conditional;
use HTML::Template::Compiled::Expression::Function;

sub _expr_close { HTML::Template::Compiled::Expression::Close->new }
sub _expr_else { HTML::Template::Compiled::Expression::Else->new }
sub _expr_literal { HTML::Template::Compiled::Expression::Literal->new(@_) }
sub _expr_defined { HTML::Template::Compiled::Expression::Defined->new(@_) }
sub _expr_ternary { HTML::Template::Compiled::Expression::Ternary->new(@_) }
sub _expr_string { HTML::Template::Compiled::Expression::String->new(@_) }
sub _expr_function { HTML::Template::Compiled::Expression::Function->new(@_) }
sub _expr_method { HTML::Template::Compiled::Expression::Method->new(@_) }


package HTML::Template::Compiled::Expression::Close;
use strict;
use warnings;
use base qw(HTML::Template::Compiled::Expression);

sub to_string {
    my ($self, $level) = @_;
    my $indent = $self->level2indent($level);
    return $indent . '}';
}


package HTML::Template::Compiled::Expression::Defined;
use strict;
use warnings;
use base qw(HTML::Template::Compiled::Expression);

sub init {
    my ($self, $op) = @_;
    $self->set_operands([$op]);
}
sub to_string {
    my ($self) = @_;
    my ($op) = $self->get_operands;
    return "defined ( " . $op->to_string . " )";
}

package HTML::Template::Compiled::Expression::Literal;
use strict;
use warnings;
use base qw(HTML::Template::Compiled::Expression);

sub init {
    my ($self, $op) = @_;
    $self->set_operands([$op]);
}

sub to_string {
    my ($self) = @_;
    my ($op) = $self->get_operands;
    return "$op";
}

package HTML::Template::Compiled::Expression::String;
use strict;
use warnings;
use Data::Dumper;
use base qw(HTML::Template::Compiled::Expression);

sub init {
    my ($self, $op) = @_;
    $self->set_operands([$op]);
}
sub to_string {
    my ($self) = @_;
    my ($op) = $self->get_operands;
    my $dump = Data::Dumper->Dump([\$op], ['op']);
    $dump =~ s#^\$op *= *\\##;
    return $dump;
}

package HTML::Template::Compiled::Expression::Ternary;
use strict;
use warnings;
use base qw(HTML::Template::Compiled::Expression);

sub init {
    my ($self, @ops) = @_;
    $self->set_operands([@ops]);
}
sub to_string {
    my ($self,$level) = @_;
    my $indent = $self->level2indent($level);
    my ($bool, $true, $false) = $self->get_operands;
    return $indent . $bool->to_string($level) . ' ? ' .
        $true->to_string($level) . ' : ' . $false->to_string($level);
}

1;

