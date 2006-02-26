# Before `make install' is performed this script should be runnable with
# `make test'. After `make install' it should work as `perl HTML-Template-Compiled.t'
# $Id: 01_HTML-Template-Compiled.t,v 1.13 2006/01/11 22:41:47 tinita Exp $

use lib 'blib/lib';
use Test::More tests => 6;
use Data::Dumper;
local $Data::Dumper::Indent = 1; local $Data::Dumper::Sortkeys = 1;
BEGIN { use_ok('HTML::Template::Compiled') };
$HTML::Template::Compiled::NEW_CHECK = 2;
use Fcntl qw(:seek);

# Insert your test code below, the Test::More module is use()ed here so read
# its man page ( perldoc Test::More ) for help writing this test script.

my $hash = {
	SELF => '/path/to/script.pl',
	LANGUAGE => 'de',
	BAND => 'Bauhaus',
	ALBUMS => [
		{
			ALBUM => 1,
			NAME => 'Mask',
			SONGS => [
				{ NAME => 'Hair of the Dog' },
				{ NAME => 'Passion of Lovers' },
		 	],
		},
	],
	INFO => {
		BIOGRAPHY => undef,
		LINK => 'http://...'
	},
	OBJECT => bless({
			'_key' => 23,
		}, "HTC::Test"),
	URITEST => 'a b c & d',
};
sub HTC::Test::key { return $_[0]->{"_key"} }

#my $cache = File::Spec->catfile('t', 'cache');
use lib 't';
use HTC_Utils qw($cache $tdir &cdir);
mkdir $cache unless -d $cache;
my $include = cdir($tdir,'include.html');
my %args = (
	path => $tdir,
	#case_insensitive => 1,
	case_sensitive => 0,
	loop_context_vars => 1,
	line_numbers => 1,
	filename => 'songs.html',
	method_call => '/',
	deref => '.',
	debug => $ENV{HARNESS_ACTIVE} ? 0 : 1,
	# for testing without cache comment out
	cache_dir => $cache,
	dumper => sub {Data::Dumper->Dump([$_[0]],['DUMP'])},
);
sleep 2;
my $htc = HTML::Template::Compiled->new(%args);
ok($htc, "template created");
$htc->param(%$hash);

eval { require HTML::Entities };
my $entities = $@ ? 0 : 1;
eval { require URI::Escape };
my $uri = $@ ? 0 : 1;
SKIP: {
	skip "no HTML::Entities and URI::Escape installed", 3, unless ($entities && $uri);
	my $out = $htc->output;
	my $dump = <<'EOM';
$DUMP = {
'BIOGRAPHY' => undef,
'LINK' => 'http://...'
};
EOM
	HTML::Entities::encode_entities($dump);
	my $exp = <<'EOM' . $dump . <<'EOM';
/path/to/script.pl?lang=de
Band: Bauhaus
Albums:
(first) (last)
Mask (Album)
1. Hair of the Dog
2. Passion of Lovers
---
Bio: No bio available
Homepage: http://...
EOM
Bio: No bio available
Homepage: http://...
Song 0: Hair of the Dog
a%20b%20c%20%26%20d
INCLUDED: Hair of the Dog
23
23
EOM
	for ($exp, $out) { s/^\s+//mg; tr/\n\r//d; }
	cmp_ok($exp, "eq", $out, "output ok");
	open my $fh, '+<', $include or die $!;
	local $/;
	my $txt = <$fh>;
	$txt =~ s/INCLUDED/INCLUDED_NEW/;
	seek $fh, 0, SEEK_SET;
	truncate $fh, 0;
	print $fh $txt;
	close $fh;
	my $htc = HTML::Template::Compiled->new(%args);
	$htc->param(%$hash);
	$out = $htc->output;
	$out =~ s/^\s+//mg; $out =~ tr/\n\r//d;
	cmp_ok($exp, "eq", $out, "output after update ok");
	$exp =~ s/INCLUDED/INCLUDED_NEW/;
	sleep 2;
	$htc = HTML::Template::Compiled->new(%args);
	$htc->param(%$hash);
	$out = $htc->output;
	$out =~ s/^\s+//mg; $out =~ tr/\n\r//d;
	cmp_ok($exp,"eq", $out, "output after update & sleep ok");
	open $fh, '+<', $include or die $!;
	local $/;
	$txt = <$fh>;
	$txt =~ s/INCLUDED_NEW/INCLUDED/;
	seek $fh, 0, SEEK_SET;
	truncate $fh, 0;
	print $fh $txt;
	close $fh;
}
{
	open my $fh, '<', $include or die $!;
	my $htc = HTML::Template::Compiled->new(
		filehandle => $fh,
	);
	$htc->param(%$hash);
	my $out = $htc->output;
	#print STDERR "out: '$out'\n";
	cmp_ok($out, "eq", "INCLUDED: Hair of the Dog\n", "filehandle output");

}

