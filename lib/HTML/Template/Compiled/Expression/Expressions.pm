# $Id: Expressions.pm,v 1.9 2006/07/17 22:57:15 tinita Exp $

package HTML::Template::Compiled::Expression::Close;
use strict;
use warnings;
use base qw(HTML::Template::Compiled::Expression);

sub to_string {
    my ($self, $level) = @_;
    my $indent = $self->level2indent($level);
    return $indent . '}';
}

package HTML::Template::Compiled::Expression::Open;
use strict;
use warnings;
use base qw(HTML::Template::Compiled::Expression);

sub to_string {
    my ($self, $level) = @_;
    my $indent = $self->level2indent($level);
    return $indent . '{';
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

