# Before `make install' is performed this script should be runnable with
# `make test'. After `make install' it should work as `perl HTML-Template-Compiled.t'
# $Id: 02_version.t,v 1.1 2005/09/19 20:59:43 tinita Exp $

use Test::More tests => 2;
BEGIN { use_ok('HTML::Template::Compiled') };

ok(HTML::Template::Compiled->__test_version, "version ok");
