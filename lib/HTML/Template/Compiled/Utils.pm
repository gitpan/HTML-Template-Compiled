package HTML::Template::Compiled::Utils;
# $Id: Utils.pm,v 1.2 2005/09/19 22:43:02 tinita Exp $
$VERSION = "0.01";
use strict;
use warnings;

use base 'Exporter';
use vars qw/@EXPORT_OK %EXPORT_TAGS/;
@EXPORT_OK = qw/PATH_METHOD PATH_DEREF/;
%EXPORT_TAGS = (walkpath => [qw/PATH_METHOD PATH_DEREF/]);

use constant PATH_METHOD => 1;
use constant PATH_DEREF => 2;

1;
__END__

=pod

=head1 NAME

HTML::Template::Compiled::Utils - Utility functions for HTML::Template::Compiled

=cut

