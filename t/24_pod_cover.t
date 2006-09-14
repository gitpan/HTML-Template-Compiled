# $Id: 24_pod_cover.t,v 1.4 2006/09/13 22:07:22 tinita Exp $
use blib; # for development

use Test::More;
eval "use Test::Pod::Coverage 1.00";
plan skip_all => "Test::Pod::Coverage required for testing pod coverage" if $@;
plan tests => 3;
# thanks to mark, at least HTC::Utils is covered...
pod_coverage_ok( "HTML::Template::Compiled::Utils", "HTC::Utils is covered");
pod_coverage_ok( "HTML::Template::Compiled::Plugin::XMLEscape", "HTC::Plugin::XMLEscape is covered");
pod_coverage_ok( "HTML::Template::Compiled::Classic", "HTML::Template::Compiled::Classic is covered");

