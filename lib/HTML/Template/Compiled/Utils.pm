package HTML::Template::Compiled::Utils;
# $Id: Utils.pm,v 1.10 2006/07/14 16:27:29 markjugg Exp $
$VERSION = "0.03";
use strict;
use warnings;
use Data::Dumper;

use base 'Exporter';
use vars qw/@EXPORT_OK %EXPORT_TAGS/;
my @paths = qw(PATH_METHOD PATH_DEREF PATH_FORMATTER);
@EXPORT_OK = (
    @paths, qw(
        &log &stack
        &escape_html &escape_uri &escape_js
    )
);
%EXPORT_TAGS = (
	walkpath => \@paths,
	log => [qw(&log &stack)],
	escape => [qw(&escape_html &escape_uri &escape_js)],
);

# These should be better documented
use constant PATH_METHOD => 1;
use constant PATH_DEREF => 2;
use constant PATH_FORMATTER => 3;

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
    my $var = shift;
    my $new = $var;

    # we have to do this cause HTML::Entities changes its arg
    # doesn't do that in the latest version and i'm not sure
    # how it behaved before
    HTML::Entities::encode_entities($new);
    return $new;
}

=head2 escape_uri

  my $escaped_uri = escape_uri($raw_uri);

URI-escapes the input string and returns it;

=cut

sub escape_uri {
    return URI::Escape::uri_escape( $_[0] );
}

=head2 escape_js

  my $escaped_js = escape_js($raw_js);

JavaScript-escapes the input string and returns it;

=cut

sub escape_js {
    my ($var) = @_;
    $var =~ s/(["'])/\\$1/g;
    $var =~ s/\r/\\r/g;
    $var =~ s/\n/\\n/g;
    return $var;
}

1;
__END__


