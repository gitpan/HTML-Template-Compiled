#!/usr/bin/perl
use strict;
use warnings;
use lib qw(blib/lib ../blib/lib);
my %use = (
	'HTML::Template' => 0,
	'HTML::Template::Compiled' => 0,
	'HTML::Template::JIT' => 0,
	'Template' => 0,
);
for my $key (keys %use) {
	eval "require $key";
	$use{$key} = 1 unless $@;
    print "using $key " . ($use{$key}?"yes":"no")."\n";
}
use Benchmark;
$HTML::Template::Compiled::NEW_CHECK = 30; # 30sec
my $debug = 0;
$ENV{'HTML_TEMPLATE_ROOT'} = "examples";
sub new_htc {
	my $t1 = HTML::Template::Compiled->new(
		#path => 'examples',
		#case_insensitive => 1, # slow down
		loop_context_vars => 1,
		filename => 'test.html',
		debug => $debug,
		# note that you have to create the cachedir
		# first, otherwise it will run without cache
		#cache_dir => "cache/htc",
	);
	return $t1;
}
sub new_ht {
	my $t2 = HTML::Template->new(
		loop_context_vars => 1,
		#path => 'examples',
		filename => 'test.html',
		cache => 1,
	);
	return $t2;
}
sub new_htj {
	my $t2 = HTML::Template::JIT->new(
		loop_context_vars => 1,
		#path => 'examples',
		filename => 'test.html',
		cache => 1,
		jit_path => '/tmp/jit',
	);
	return $t2;
}
sub new_tt {
	my $tt= Template->new(
		COMPILE_EXT => '.ttc',
		COMPILE_DIR => 'cache/tt',
	);
}
my %params = (
	name => 'merlyn',
	loopa => [{a=>3},{a=>4},{a=>5}],
	#a => [qw(b c d)],
	loopb => [{ inner => 23 }],
	c => [
	 {
		 d=>[({F=>11},{F=>22}, {F=>33})]
	 },
	{
		d=>[({F=>44}, {F=>55}, {F=>66})]
	}
	],
	if2 => 1,
	if3 => 0,
	blubber => "html <test>",
);
sub output {
	my $t = shift;
	return unless defined $t;
	$t->param(%params);
	#print $t->{code} if exists $t->{code};
	my $out = $t->output;
	#print "\nOUT: $out";
}
open TT_OUT, ">>/dev/null";
#open TT_OUT, ">&STDOUT";
sub output_tt {
	my $t = shift;
	return unless defined $t;
	my $filett = "examples/test.tt";
	$t->process($filett, \%params, \*TT_OUT);
	#print $t->{code} if exists $t->{code};
	#my $out = $t->output;
	#print "\nOUT: $out";
}

my $gobal_htc = $use{'HTML::Template::Compiled'} ? new_htc : undef;
my $gobal_ht = $use{'HTML::Template'} ? new_ht : undef;;
my $gobal_htj = $use{'HTML::Template::JIT'} ? new_htj : undef;;
my $gobal_tt = $use{'Template'} ? new_tt : undef;;
if(1) {
timethese ($ARGV[0]||100, {
		$use{'HTML::Template::Compiled'} ? (
            # deactivate memory cache
            #new_htc_w_clear_cache => sub {my $t = new_htc();$t->clear_cache},
            # normal, with memory cache
            new_htc => sub {my $t = new_htc()},
            output_htc => sub {output($gobal_htc)},
        ) : (),
		$use{'HTML::Template'} ? (
            new_ht => sub {my $t = new_ht()},
            output_ht => sub {output($gobal_ht)},
        ) : (),
        $use{'HTML::Template::JIT'} ? (
            new_htj => sub {my $t = new_htj();},
            output_htj => sub {output($gobal_htj)},
        ) : (),
        $use{'Template'} ? (
            new_tt => sub {my $t = new_tt();},
            output_tt => sub {output_tt($gobal_tt)},
        ): (),
	});
}
__END__
my $file = "templates/test.tt";
my $filehtc = "test.htc";
$tt->process($file, $vars,);
