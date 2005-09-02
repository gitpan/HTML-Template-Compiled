package HTML::Template::Compiled::Utils;
# $Id: Utils.pm,v 1.1 2005/09/01 23:32:28 tina Exp $
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
