package HTML::Template::Compiled::Classic;
# $Id: Classic.pm,v 1.3 2006/07/03 00:31:04 tinita Exp $
use strict;
use warnings;
our $VERSION = "0.01";

use base 'HTML::Template::Compiled';

sub _get_var_sub {
    my ($self, $P, $ref, $final, @paths) = @_;
    my $var = $ref->{$paths[0]->[1]};
    ref $var eq 'CODE' and $var = $var->();
    return $var;
}

sub _get_var_global_sub {
    my ($self, $P, $ref, $final, @paths) = @_;
    my $key = $paths[0]->[1];
    my $stack = $self->getGlobalstack || [];
    for my $item ( $ref, reverse @$stack ) {
        next unless exists $item->{$key};
        my $var = $item->{$key};
        ref $var eq 'CODE' and $var = $var->();
        return $var;
    }
    return;
}

sub _make_path {
    my ( $self, %args ) = @_;
    if ( $self->getLoop_context && $args{var} =~ m/^__(\w+)__$/ ) {
        return "\$\L$args{var}\E";
    }
    my $getvar = '_get_var'
        . ($self->getGlobal_vars&1 ? '_global' : '')
        . '_sub';
    my $varstr =
        "\$t->$getvar(" . '$P,$$C,0,'."[undef,'$args{var}'])";
    return $varstr;
}


1;

__END__

=head1 NAME

HTML::Template::Compiled::Classic

=head1 SYNOPSIS

    use HTML::Template::Compiled::Classic;
    my $htcc = HTML::Template::Compiled::Classic->new(
        # usual parameters for HTML::Template::Compiled
    );

=head1 DESCRIPTION

This class provides features which can not be used together with
features from L<HTML::Template::Compiled>. These are:

=over 4

=item dots in TMPL_VARs

If you want to use

  <TMPL_VAR NAME="some.var.with.dots">

you cannot use the dot-feature

  <TMPL_VAR NAME="some.hash.keys">

at the same time.

=item Subref variables

In L<HTML::Template>, the following works:

    my $ht = HTML::Template->new(
        scalarref => \"<TMPL_VAR foo>",
    );
    $ht->param(foo => sub { return "bar" });
    print $ht->output; # prints 'bar'

This doesn't work in L<HTML::Template::Compiled> (in the past it did,
but as of this version it won't any more, sorry).

=back

=cut

