# Before `make install' is performed this script should be runnable with
# `make test'. After `make install' it should work as `perl HTML-Template-Compiled.t'
# $Id: 07_formatter.t,v 1.2 2005/11/21 21:19:21 tinita Exp $

use lib 'blib/lib';
use Test::More tests => 2;
BEGIN { use_ok('HTML::Template::Compiled') };

my $formatter = {
	'HTC::Class1' => {
		fullname => sub {
			$_[0]->first . ' ' . $_[0]->last
		},
		first => HTC::Class1->can('first'),
		last => HTC::Class1->can('last'),
	},
};
my $htc = HTML::Template::Compiled->new(
	path => 't/templates',
	filename => 'formatter.htc',
	debug => 0,
	formatter => $formatter,
);
my $obj = bless ({ first => 'Abi', last => 'Gail'}, 'HTC::Class1');

$htc->param(
	test => 23,
	obj => $obj,
);
my $out = $htc->output;
my $exp = <<EOM;
23
Abi plus Gail
Abi Gail
EOM
for ($exp, $out) {
	tr/\r\n//d;
}
ok($exp eq $out, "formatter");
sub HTC::Class1::first {
	$_[0]->{first}
}
sub HTC::Class1::last {
	$_[0]->{last}
}

__END__
<%= test%>
<%= obj/first %> plus <%= obj/last%>
<%= obj/fullname%>
