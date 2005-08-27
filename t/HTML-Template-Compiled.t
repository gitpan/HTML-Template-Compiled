# Before `make install' is performed this script should be runnable with
# `make test'. After `make install' it should work as `perl HTML-Template-Compiled.t'
# $Id: HTML-Template-Compiled.t,v 1.15 2005/08/27 00:48:48 tina Exp $

#########################

# change 'tests => 1' to 'tests => last_test_to_print';

use lib 'blib/lib';
use Test::More tests => 7;
BEGIN { use_ok('HTML::Template::Compiled') };
$HTML::Template::Compiled::NEW_CHECK = 2;
use Fcntl qw(:seek);

ok(HTML::Template::Compiled->__test_version, "version ok");

#########################

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
	URITEST => 'a b c & d',
	OBJECT => bless({
			'_key' => 23,
		}, "HTC::Test"),
};
sub HTC::Test::key { return $_[0]->{"_key"} }

my %args = (
	path => 't',
	#case_insensitive => 1,
	case_sensitive => 0,
	loop_context_vars => 1,
	line_numbers => 1,
	filename => 'songs.html',
	method_call => '/',
	deref => '.',
	debug => $ENV{HARNESS_ACTIVE} ? 0 : 1,
	# for testing without cache comment out
	cache_dir => "cache",
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
if ($entities && $uri) {
	my $out = $htc->output;
	my $exp = <<EOM;
<a href="/path/to/script.pl?lang=de">Start</a><br>
Band: Bauhaus<br>
Albums:
(first)
(last)
<b>Mask</b>(Album)<br>
1. Hair of the Dog<br>
2. Passion of Lovers<br>
<hr>
Bio: <p>No bio available</p>
Homepage: <a href="http://...">Start</a>
\$DUMP = {
'BIOGRAPHY' =&gt; undef,
'LINK' =&gt; 'http://...'
};
Bio: <p>No bio available</p>
Homepage: <a href="http://...">Start</a>
Hair of the Dog
a%20b%20c%20%26%20d
INCLUDED: Hair of the Dog
23
23
EOM
	for ($exp, $out) { s/^\s+//mg; tr/\n//s; }
	print "($exp)\n($out)\n" unless $ENV{HARNESS_ACTIVE};
	ok($exp eq $out, "output ok");
	open my $fh, '+<', 't/include.html' or die $!;
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
	$out =~ s/^\s+//mg; $out =~ tr/\n//s;
	ok($exp eq $out, "output after update ok");
	$exp =~ s/INCLUDED/INCLUDED_NEW/;
	sleep 2;
	$htc = HTML::Template::Compiled->new(%args);
	$htc->param(%$hash);
	$out = $htc->output;
	$out =~ s/^\s+//mg; $out =~ tr/\n//s;
	ok($exp eq $out, "output after update & sleep ok");
	open $fh, '+<', 't/include.html' or die $!;
	local $/;
	$txt = <$fh>;
	$txt =~ s/INCLUDED_NEW/INCLUDED/;
	seek $fh, 0, SEEK_SET;
	truncate $fh, 0;
	print $fh $txt;
	close $fh;
}
else {
	# we don't have the escaping modules, can't test
	ok(1, "dummy test");
}
my $wrong;
eval {
$wrong = HTML::Template::Compiled->new(
	path => 't',
	line_numbers => 1,
	filename => 'wrong.html',
	debug => $ENV{HARNESS_ACTIVE} ? 0 : 1,
	);
};
print "err: $@\n" unless $ENV{HARNESS_ACTIVE};
ok($@, "wrong template");

