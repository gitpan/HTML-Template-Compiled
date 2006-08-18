# $Id: 24_pod_cover.t,v 1.2 2006/07/17 21:48:34 tinita Exp $
use blib; # for development

use Test::More;
eval "use Test::Pod::Coverage 1.00";
plan skip_all => "Test::Pod::Coverage required for testing pod coverage" if $@;
plan tests => 1;
# thanks to mark, at least HTC::Utils is covered...
pod_coverage_ok( "HTML::Template::Compiled::Utils", "HTML::Template::Compiled::Utils is covered");

