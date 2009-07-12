#!/usr/bin/perl

package HTC::Object;
use strict;
use warnings;
use base qw(Class::Accessor);
__PACKAGE__->follow_best_practice;
__PACKAGE__->mk_accessors(qw(first last age));

package main;
use strict;
use warnings;
use HTML::Template::Compiled::Formatter;
use Fcntl qw(:seek);

my ($template, $perlcode);
{
    local $/;
    $template = <DATA>;
    seek DATA, 0, SEEK_SET;
    $perlcode = <DATA>;
}
my $formatter = {
    'HTC::Object' => {
        fullname => sub {
            my $first = $_[0]->get_first;
            my $last = $_[0]->get_last;
            return "$last, $first";
        },
    },
};

local $HTML::Template::Compiled::Formatter::formatter = $formatter;

my $htc = HTML::Template::Compiled::Formatter->new(
    scalarref => \$template,
    tagstyle => [qw(+tt)],
);
my $persons = [
    HTC::Object->new({first => 'Bart',   last => 'Simpson', age => 10}),
    HTC::Object->new({first => 'Maggie', last => 'Simpson', age => 10}),
    HTC::Object->new({first => 'March',  last => 'Simpson', age => 42}),
    HTC::Object->new({first => 'Homer',  last => 'Simpson', age => 42}),
];
$htc->param(
    count => scalar @$persons,
    items => $persons,
    script => $0,
    perlcode => $perlcode,
);
my $output = $htc->output;
print $output;

__DATA__
<html><head><title>HTC example with objects</title></head>
<body>
<h2>Script: [%= .script %]</h2><p>
Found [%= .count %] persons:
<table>
<tr><th>Name</th><th>Age</th></tr>
[%loop items%]
<tr>
    <td>[%= _/fullname %]</td>
    <td>[%= get_age %]</td>
</tr>
[%/loop items%]
</table>
<hr>
<h2>The Script:</h2>
<pre>
[%= perlcode escape=html %]
</pre>
</body></html>
