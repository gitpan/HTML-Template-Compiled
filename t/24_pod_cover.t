# $Id: 24_pod_cover.t,v 1.3 2006/08/26 12:03:37 tinita Exp $
use blib; # for development

use Test::More;
eval "use Test::Pod::Coverage 1.00";
plan skip_all => "Test::Pod::Coverage required for testing pod coverage" if $@;
plan tests => 2;
# thanks to mark, at least HTC::Utils is covered...
pod_coverage_ok( "HTML::Template::Compiled::Utils", "HTC::Utils is covered");
pod_coverage_ok( "HTML::Template::Compiled::Plugin::XMLEscape", "HTC::Plugin::XMLEscape is covered");

