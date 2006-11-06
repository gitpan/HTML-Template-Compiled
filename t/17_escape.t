# Before `make install' is performed this script should be runnable with
# `make test'. After `make install' it should work as `perl HTML-Template-Compiled.t'
# $Id: 17_escape.t,v 1.5 2006/11/06 19:05:41 tinita Exp $

use lib 'blib/lib';
use Test::More tests => 4;
use Data::Dumper;
use File::Spec;
use strict;
use warnings;
local $Data::Dumper::Indent = 1; local $Data::Dumper::Sortkeys = 1;
BEGIN { use_ok('HTML::Template::Compiled') };
BEGIN { use_ok('HTML::Template::Compiled::Plugin::XMLEscape') };
$HTML::Template::Compiled::NEW_CHECK = 2;
my $cache = File::Spec->catfile('t', 'cache');

eval { require HTML::Entities };
my $entities = $@ ? 0 : 1;

SKIP: {
	skip "no HTML::Entities installed", 3, unless $entities;
	
	my $htc = HTML::Template::Compiled->new(
		scalarref => \<<'EOM',
<tmpl_var html>
<tmpl_var nohtml ESCAPE=0>
EOM
		default_escape => 'HTML',
		debug => 0,
	);
	my $html = '<html>';
	my $nohtml = $html;
	$htc->param(
		html => $html,
		nohtml => $nohtml,
	);
	HTML::Entities::encode_entities($html);
	my $out = $htc->output;
	$out =~ tr/\n\r //d;
	#print $out,$/;
	cmp_ok($out, "eq", $html . $nohtml, "default_escape");
}

{

    my $htc = HTML::Template::Compiled->new(
        scalarref => \<<"EOM",
        <xml foo="<%= foo escape=xml_attr %>"><%= foo escape=xml %></xml>
EOM
        plugin => [qw(::XMLEscape)],
        debug => 0,
    );
    #warn Data::Dumper->Dump([\$htc], ['htc']);
    my $foo = "<to_escape>";
    my $xml = HTML::Template::Compiled::Plugin::XMLEscape::escape_xml($foo);
    my $xml_attr = HTML::Template::Compiled::Plugin::XMLEscape::escape_xml_attr($foo);
    $htc->param(foo => $foo);
    my $out = $htc->output;
	$out =~ tr/\n\r//d;
    $out =~ s/^\s*//;
    #print $out, $/;
    cmp_ok($out, 'eq', qq{<xml foo="$xml_attr">$xml</xml>}, "Plugin XMLEscape");
}
