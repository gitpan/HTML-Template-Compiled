package HTML::Template::Compiled::Utils;
# $Id: Utils.pm,v 1.7 2006/05/29 18:30:11 tinita Exp $
$VERSION = "0.02";
use strict;
use warnings;
use Data::Dumper;

use base 'Exporter';
use vars qw/@EXPORT_OK %EXPORT_TAGS/;
my @paths = qw(PATH_METHOD PATH_DEREF PATH_FORMATTER);
@EXPORT_OK = (
    @paths, qw(
        &log &stack
        &escape_html &escape_uri
    )
);
%EXPORT_TAGS = (
	walkpath => \@paths,
	log => [qw(&log &stack)],
	escape => [qw(&escape_html &escape_uri)],
);

use constant PATH_METHOD => 1;
use constant PATH_DEREF => 2;
use constant PATH_FORMATTER => 3;

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

sub escape_html {
    my ( $self, $var ) = @_;
    my $new = $var;

    # we have to do this cause HTML::Entities changes its arg
    # doesn't do that in the latest version and i'm not sure
    # how it behaved before
    HTML::Entities::encode_entities($new);
    return $new;
}

sub escape_uri {
    return URI::Escape::uri_escape( $_[1] );
}


1;
__END__

=pod

=head1 NAME

HTML::Template::Compiled::Utils - Utility functions for HTML::Template::Compiled

=cut

