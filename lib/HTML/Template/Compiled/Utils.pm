package HTML::Template::Compiled::Utils;
# $Id: Utils.pm,v 1.17 2007/07/17 20:08:42 tinita Exp $
$VERSION = "0.04";
use strict;
use warnings;
use Data::Dumper qw(Dumper);

use base 'Exporter';
use vars qw/@EXPORT_OK %EXPORT_TAGS/;
my @paths = qw(PATH_METHOD PATH_DEREF PATH_FORMATTER PATH_ARRAY);
@EXPORT_OK = (
    @paths, qw(
        &log &stack
        &escape_html &escape_html_all &escape_uri &escape_js
        &md5
    )
);
%EXPORT_TAGS = (
	walkpath => \@paths,
	log => [qw(&log &stack)],
	escape => [qw(&escape_html &escape_uri &escape_js)],
);

# These should be better documented
# these might be obsolete soon =)
use constant PATH_METHOD => 1;
use constant PATH_DEREF => 2;
use constant PATH_FORMATTER => 3;
use constant PATH_ARRAY => 4;

my $digest_md5 = 0;
eval {
    require Digest::MD5;
};
unless ($@) {
    $digest_md5 = 1;
}

=pod

=head1 NAME

HTML::Template::Compiled::Utils - Utility functions for HTML::Template::Compiled

=head1 SYNOPSIS
 
 # import log() and stack()
 use HTML::Template::Compiled::Utils qw(:log);

 # import the escapign functions
 use HTML::Template::Compiled::Utils qw(:escape);


=head1 DEBUGGING FUNCTIONS

=cut

=head2 stack

    $self->stack;

For HTML::Template:Compiled developers, prints a stack trace to STDERR.

=cut

=head2 md5

 md5($text)

If L<Digest::MD5> is installed, returns the md5_base64 for C<$text>,
otherwise returns the empty string.

=cut

sub md5 {
    my ($text) = @_;
    if ($digest_md5) {
        return Digest::MD5::md5_base64($text);
    }
    return '';
}

sub stack {
    my ( $self, $force ) = @_;
    return if !HTML::Template::Compiled::D() and !$force;
    my $i = 0;
    my $out;
    while ( my @c = caller($i) ) {
        $out .= "$i\t$c[0] l. $c[2] $c[3]\n";
        $i++;
    }
    print STDERR $out;
}

=head2 log

 $self->log(@msg)

For HTML::Template::Compiled developers, print log from C<@msg> to STDERR.

=cut

sub log {
    #return unless D;
    my ( $self, @msg ) = @_;
    my @c  = caller();
    my @c2 = caller(1);
    print STDERR "----------- ($c[0] line $c[2] $c2[3])\n";
    for (@msg) {
        if ( !defined $_ ) {
            print STDERR "---  UNDEF\n";
        }
        elsif ( !ref $_ ) {
            print STDERR "--- $_\n";
        }
        else {
            if ( ref $_ eq __PACKAGE__ ) {
                print STDERR "DUMP HTC\n";
                for my $m (qw(file perl)) {
                    my $s = "get" . ucfirst $m;
                    print STDERR "\t$m:\t", $_->$s || "UNDEF", "\n";
                }
            }
            else {
                print STDERR "--- DUMP ---: " . Dumper $_;
            }
        }
    }
}

=head1 ESCAPING FUNCTIONS

=head2 escape_html

  my $escaped_html = escape_html($raw_html);

HTML-escapes the input string and returns it;

=cut

sub escape_html {
    my ($str) = @_;
    $str =~ s/&/&amp;/g;
    $str =~ s/"/&quot;/g;
    $str =~ s/'/&#39;/g;
    $str =~ s/>/&gt;/g;
    $str =~ s/</&lt;/g;
    return $str;
}

=head2 escape_html_all

  my $escaped_html = escape_html($raw_html);

HTML-escapes the input string and returns it;

=cut

sub escape_html_all {
    # hopefully encode_entities() works correct
    # and doesn't change its arg when called in scalar context
    return HTML::Entities::encode_entities($_[0]);
}

=head2 escape_uri

  my $escaped_uri = escape_uri($raw_uri);

URI-escapes the input string and returns it;

=cut

eval { require Encode };
my $encode = $@ ? 0 : 1;
sub escape_uri {
    # if we want to use utf8 we require Encode.pm to be installed
    my $x = ($encode and Encode::is_utf8($_[0]))
        ? URI::Escape::uri_escape_utf8( $_[0] )
        : URI::Escape::uri_escape( $_[0] );
    return $x;
}

=head2 escape_js

  my $escaped_js = escape_js($raw_js);

JavaScript-escapes the input string and returns it;

=cut

sub escape_js {
    my ($var) = @_;
    return $var unless defined $var;
    $var =~ s/(["'])/\\$1/g;
    $var =~ s/\r/\\r/g;
    $var =~ s/\n/\\n/g;
    return $var;
}

1;
__END__


