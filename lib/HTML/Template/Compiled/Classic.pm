package HTML::Template::Compiled::Classic;
# $Id: Classic.pm,v 1.11 2006/09/29 00:01:31 tinita Exp $
use strict;
use warnings;
our $VERSION = "0.04";

use base 'HTML::Template::Compiled';
use HTML::Template::Compiled::Compiler::Classic;

sub compiler_class { 'HTML::Template::Compiled::Compiler::Classic' }

#sub _get_var_sub {
#    my ($self, $P, $ref, $final, @paths) = @_;
#    my $var = $ref->{$paths[0]->[1]};
#    ref $var eq 'CODE' and $var = $var->();
#    return $var;
#}

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


1;

__END__

=head1 NAME

HTML::Template::Compiled::Classic - Provide the classic functionality like HTML::Template

=head1 SYNOPSIS

    use HTML::Template::Compiled::Classic compatible => 1;
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
but as of HTC version 0.70 it won't any more, sorry).

=back

=head1 METHODS

=over 4

=item compiler_class

returns HTML::Template::Compiled::Compiler::Classic

=back

=cut

