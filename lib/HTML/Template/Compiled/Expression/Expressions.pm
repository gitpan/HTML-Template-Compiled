package HTML::Template::Compiled::Expression::Expressions;
# $Id: Expressions.pm 1093 2009-07-11 15:41:37Z tinita $
use strict;
use warnings;

package HTML::Template::Compiled::Expression::Defined;
use base qw(HTML::Template::Compiled::Expression);

sub init {
    my ($self, $op) = @_;
    $self->set_operands([$op]);
}
sub to_string {
    my ($self) = @_;
    my ($op) = $self->get_operands;
    return "defined ( " . (ref $op ? $op->to_string : $op) . " )";
}

package HTML::Template::Compiled::Expression::Literal;
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
    $dump =~ s/;$//;
    return $dump;
}

package HTML::Template::Compiled::Expression::Ternary;
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
        (ref $true ? $true->to_string($level) : $true)
        . ' : ' . (ref $false ? $false->to_string($level) : $false);
}

1;

