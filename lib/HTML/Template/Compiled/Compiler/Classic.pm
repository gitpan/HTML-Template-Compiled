package HTML::Template::Compiled::Compiler::Classic;
# $Id: Classic.pm,v 1.1 2006/09/13 22:00:56 tinita Exp $
use strict;
use warnings;
our $VERSION = "0.01";

use base 'HTML::Template::Compiled::Compiler';

sub _make_path {
    my ( $self, $t, %args ) = @_;
    my %loop_context = (
        __index__   => '$__ix__',
        __counter__ => '$__ix__+1',
        __first__   => '$__ix__ == $[',
        __last__    => '$__ix__ == $size',
        __odd__     => '!($__ix__ & 1)',
        __inner__   => '$__ix__ != $[ && $__ix__ != $size',
    );

    if ( $t->getLoop_context && $args{var} =~ m/^__(\w+)__$/ ) {
        my $lc = $loop_context{ lc $args{var} };
        return $lc;
    }
    my $getvar = '_get_var'
        . ($t->getGlobal_vars&1 ? '_global' : '')
        . '_sub';
    my $varstr =
        "\$t->$getvar(" . '$P,$$C,0,'."[undef,'$args{var}'])";
    return $varstr;
}


1;

__END__

=head1 NAME

HTML::Template::Compiled::Compiler::Classic - Provide the classic functionality like HTML::Template

=head1 DESCRIPTION

This is the compiler class for L<HTML::Template::Compiled::Classic>

=head1 METHODS

=over 4

=item _make_path

Make a path out of tmpl_var name="foobar"

=back

=cut

