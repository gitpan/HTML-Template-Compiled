package HTML::Template::Compiled::Token;
# $Id: Token.pm,v 1.4 2006/09/28 18:46:28 tinita Exp $
use strict;
use warnings;
use Carp qw(croak carp);

our $VERSION = '0.01';

use constant ATTR_TEXT       => 0;
use constant ATTR_LINE       => 1;
use constant ATTR_OPEN       => 2;
use constant ATTR_NAME       => 3;
use constant ATTR_ATTRIBUTES => 4;
use constant ATTR_CLOSE      => 5;

use constant NO_TAG        => 0;
use constant OPENING_TAG   => 1;
use constant CLOSING_TAG   => 2;

sub new {
    my ($class, @args) = @_;
    my $self;
    if (@args == 1 and ref $args[0] eq 'ARRAY') {
        $self = $args[0];
    }
    else {
        $self = [];
    }
    bless $self, $class;
    return $self;
}

sub get_text       { $_[0]->[ATTR_TEXT] }
sub set_text       { $_[0]->[ATTR_TEXT] = $_[1] }
sub get_name       { $_[0]->[ATTR_NAME] }
sub set_name       { $_[0]->[ATTR_NAME] = $_[1] }
sub get_line       { $_[0]->[ATTR_LINE] }
sub set_line       { $_[0]->[ATTR_LINE] = $_[1] }
sub get_open       { $_[0]->[ATTR_OPEN] }
sub set_open       { $_[0]->[ATTR_OPEN] = $_[1] }
sub get_close      { $_[0]->[ATTR_CLOSE] }
sub set_close      { $_[0]->[ATTR_CLOSE] = $_[1] }
sub get_attributes { $_[0]->[ATTR_ATTRIBUTES] }
sub set_attributes { $_[0]->[ATTR_ATTRIBUTES] = $_[1] }

package HTML::Template::Compiled::Token::Text;
use Carp qw(croak carp);
use base qw(HTML::Template::Compiled::Token);

sub is_open  { 0 }
sub is_close { 0 }
sub is_tag   { 0 }

package HTML::Template::Compiled::Token::open;
use base qw(HTML::Template::Compiled::Token);
sub is_open  { 1 }
sub is_close { 0 }
sub is_tag   { 1 }

package HTML::Template::Compiled::Token::close;
use base qw(HTML::Template::Compiled::Token);
sub is_open  { 0 }
sub is_close { 1 }
sub is_tag   { 1 }

package HTML::Template::Compiled::Token::single;
use base qw(HTML::Template::Compiled::Token);
sub is_open  { 1 }
sub is_close { 0 }
sub is_tag   { 1 }

1;

__END__

=pod

=head1 NAME

HTML::Template::Compiled::Token

=cut

