# Before `make install' is performed this script should be runnable with
# `make test'. After `make install' it should work as `perl HTML-Template-Compiled.t'
# $Id: HTML-Template-Compiled.t,v 1.7 2005/08/19 18:01:49 tina Exp $

#########################

# change 'tests => 1' to 'tests => last_test_to_print';

use lib 'blib/lib';
use Test::More tests => 4;
BEGIN { use_ok('HTML::Template::Compiled') };
$HTML::Template::Compiled::NEW_CHECK = 1;

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
		BIOGRAPHY => 'Bio',
		LINK => 'http://...'
	},
	URITEST => 'a b c & d',
	OBJECT => bless({
			'_key' => 23,
		}, "HTC::Test"),
};
sub HTC::Test::key { return $_[0]->{"_key"} }

my $htc = HTML::Template::Compiled->new(
	path => 't',
	case_insensitive => 1,
	loop_context_vars => 1,
	line_numbers => 1,
	filename => 'songs.html',
	method_call => '/',
	deref => '.',
	debug => $ENV{HARNESS_ACTIVE} ? 0 : 1,
	# for testing without cache comment out
	cache_dir => "cache",
);
ok($htc, "template created");
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
0. Hair of the Dog<br>
1. Passion of Lovers<br>
<hr>
Bio: <p>Bio</p>
Homepage: <a href="http://...">Start</a>
\$DUMP = {
'BIOGRAPHY' =&gt; 'Bio',
'LINK' =&gt; 'http://...'
};
Bio: <p>Bio</p>
Homepage: <a href="http://...">Start</a>
Hair of the Dog
a%20b%20c%20%26%20d
INCLUDED: Hair of the Dog
23
23
EOM
	for ($exp, $out) {
		s/^\s+//mg;
		tr/\n//s;
	}
	print "($exp)\n($out)\n" unless $ENV{HARNESS_ACTIVE};
	ok($exp eq $out);
}
else {
	# we don't have the escaping modules, can't test
	ok(1, "dummy test");
}

