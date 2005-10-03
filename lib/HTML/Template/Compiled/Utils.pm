package HTML::Template::Compiled::Utils;
# $Id: Utils.pm,v 1.3 2005/09/26 22:11:52 tinita Exp $
$VERSION = "0.01";
use strict;
use warnings;

use base 'Exporter';
use vars qw/@EXPORT_OK %EXPORT_TAGS/;
@EXPORT_OK = qw/PATH_METHOD PATH_DEREF PATH_FORMATTER/;
%EXPORT_TAGS = (walkpath => [qw/PATH_METHOD PATH_DEREF PATH_FORMATTER/]);

use constant PATH_METHOD => 1;
use constant PATH_DEREF => 2;
use constant PATH_FORMATTER => 3;

1;
__END__

=pod

=head1 NAME

HTML::Template::Compiled::Utils - Utility functions for HTML::Template::Compiled

=cut

