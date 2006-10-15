package HTML::Template::Compiled::Compiler::Classic;
# $Id: Classic.pm,v 1.8 2006/10/11 20:52:50 tinita Exp $
use strict;
use warnings;
our $VERSION = "0.01";

use base 'HTML::Template::Compiled::Compiler';

sub parse_var {
    my ( $self, $t, %args ) = @_;
    my $context = $args{context};
    # only allow '.', '/', '+', '-' and '_'
    if (!$t->validate_var($args{var})) {
        $t->get_parser->_error_wrong_tag_syntax(
            $context->get_file, $context->get_line, "", $args{var}
        );
    }
    my %loop_context = (
        __index__   => '$__ix__',
        __counter__ => '$__ix__+1',
        __first__   => '$__ix__ == $[',
        __last__    => '$__ix__ == $size',
        __odd__     => '!($__ix__ & 1)',
        __inner__   => '$__ix__ != $[ && $__ix__ != $size',
    );

    if ( $t->get_loop_context && $args{var} =~ m/^__(\w+)__$/ ) {
        my $lc = $loop_context{ lc $args{var} };
        return $lc;
    }
    if ($t->get_global_vars & 1) {
        my $varstr =
            "\$t->_get_var_global_sub(" . '$P,$$C,0,'."[undef,'$args{var}'])";
        return $varstr;
    }
    else {
        my $var = $args{var};
        $var =~ s/\\/\\\\/g;
        $var =~ s/'/\\'/g;
        my $varstr = '$$C->{' . "'$var'" . '}';
        my $string = <<"EOM";
do { my \$var = $varstr;
  \$var = (ref \$var eq 'CODE') ?  \$var->() : \$var;
EOM
        if ($context->get_name !~ m/^(?:LOOP|WITH)$/) {
            $string .= <<"EOM";
(ref \$var eq 'ARRAY' ? \@\$var : \$var)
EOM
 }
            $string .= '}';
        return $string;
    }
}


1;

__END__

=head1 NAME

HTML::Template::Compiled::Compiler::Classic - Provide the classic functionality like HTML::Template

=head1 DESCRIPTION

This is the compiler class for L<HTML::Template::Compiled::Classic>

=head1 METHODS

=over 4

=item parse_var

Make a path out of tmpl_var name="foobar"

=back

=cut

