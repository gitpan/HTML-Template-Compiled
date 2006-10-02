# Before `make install' is performed this script should be runnable with
# `make test'. After `make install' it should work as `perl HTML-Template-Compiled.t'
# $Id: 12_path.t,v 1.4 2006/10/02 15:20:42 tinita Exp $

use lib 'blib/lib';
use Test::More tests => 3;
BEGIN { use_ok('HTML::Template::Compiled') };
use File::Spec ();

eval {
	my $htc = HTML::Template::Compiled->new(
		path => [
            File::Spec->catfile(qw(t templates_foo)),
            File::Spec->catfile(qw(t templates)),
        ],
		filename => File::Spec->catfile(qw(subdir a file1.html)),
		search_path_on_include => 0,
		#debug => 1,
	);
};
print "err: $@\n"  unless $ENV{HARNESS_ACTIVE};
ok($@ =~ m{'dummy.tmpl' not found}, "search_path_on_include off");

my $htc = HTML::Template::Compiled->new(
	path => File::Spec->catfile(qw(t templates)),
	filename => File::Spec->catfile(qw(subdir a file1.html)),
    search_path_on_include => 1,
	#debug => 1,
);
my $out = $htc->output;
$out =~ tr/\r\n//d;
ok(
	$out =~ m{Template t/templates/a/file1.htmlTemplate t/templates/a/file2.html},
	"include form current dir");
	

