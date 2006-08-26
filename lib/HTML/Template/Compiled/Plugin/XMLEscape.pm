package HTML::Template::Compiled::Plugin::XMLEscape;
# $Id: XMLEscape.pm,v 1.4 2006/08/26 14:07:14 tinita Exp $
use strict;
use warnings;
use Carp qw(croak carp);
use HTML::Template::Compiled::Expression qw(:expressions);
use HTML::Template::Compiled;
HTML::Template::Compiled->register(__PACKAGE__);

sub register {
    my ($class) = @_;
    my %plugs = (
        escape => {
            # <tmpl_var foo escape=XML>
            XML => \&escape_xml,
            XML_ATTR => 'HTML::Template::Compiled::Plugin::XMLEscape::escape_xml_attr',
        },
    );
    return \%plugs;
}

sub escape_xml {
    defined( my $escaped = $_[0] ) or return;
    $escaped =~ s/&/&amp;/g;
    $escaped =~ s/</&lt;/g;
    $escaped =~ s/>/&lt;/g;
    $escaped =~ s/"/&quot;/g;
    $escaped =~ s/'/&apos;/g;
    return $escaped;
}

sub escape_xml_attr {
    defined( my $escaped = $_[0] ) or return;
    $escaped =~ s/&/&amp;/g;
    $escaped =~ s/</&lt;/g;
    $escaped =~ s/>/&lt;/g;
    $escaped =~ s/"/&quot;/g;
    $escaped =~ s/'/&apos;/g;
    return $escaped;
}

1;

__END__

=pod

=head1 NAME

HTML::Template::Compiled::Plugin::XMLEscape - XML-Escaping for HTC

=head1 SYNOPSIS

    use HTML::Template::Compiled::Plugin::XMLEscape;
    HTML::Template::Compiled->register('HTML::Template::Compiled::Plugin::XMLEscape');

    my $htc = HTML::Template::Compiled->new(
        plugin => [qw(HTML::Template::Compiled::Plugin::XMLEscape)],
        ...
    );

=head1 METHODS

=over 4

=item register

gets called by HTC

=item escape_xml

escapes data for XML CDATA.

=item escape_xml_attr

escapes data for XML attributes

=back

=cut

