#!/usr/bin/perl
# $Id: bench.pl,v 1.12 2006/07/13 18:05:27 tinita Exp $
use strict;
use warnings;
use lib qw(blib/lib ../blib/lib);
#use Devel::Size qw(size total_size);
my $count = 0;
my $ht_file = 'test.htc';
#$ht_file = 'test.htc.10';
#$ht_file = 'test.htc.20';
my $htcc_file = $ht_file . 'c';
my $tt_file = "test.tt";
#$tt_file = "examples/test.tt.10";
#$tt_file = "examples/test.tt.20";
my $tst_file = "examples/test.tst";
mkdir "cache";
mkdir "cache/htc";
mkdir "cache/jit";
my %use = (
	'HTML::Template'           => 0,
	'HTML::Template::Compiled' => 0,
	'HTML::Template::Compiled::Classic' => 0,
	'HTML::Template::JIT'      => 0,
	'Template'                 => 0,
	# not yet
	'Text::ScriptTemplate'     => 0,
);
for my $key (sort keys %use) {
	eval "require $key";
	$use{$key} = 1 unless $@;
	my $version = $use{$key} ? $key->VERSION : "-";
    printf "using %35s %s\n", $key, $version;
}
HTML::Template::Compiled->ExpireTime(10);
use Benchmark;
my $debug = 0;
$ENV{'HTML_TEMPLATE_ROOT'} = "examples";
my $FILE_CACHE     = 0;
my $MEM_CACHE      = 1;
my $LOOP_CONTEXT   = 1;
my $GLOBAL_VARS    = 0;
my $CASE_SENSITIVE = 1;
sub new_htc {
	my $t1 = HTML::Template::Compiled->new_file( $ht_file,
		#path => 'examples',
		case_sensitive => $CASE_SENSITIVE, # slow down
		loop_context_vars => $LOOP_CONTEXT,
		debug => $debug,
		# note that you have to create the cachedir
		# first, otherwise it will run without cache
        cache_dir => ($FILE_CACHE ? "cache/htc" : undef),
        cache => $MEM_CACHE,
		out_fh => 1,
        global_vars => $GLOBAL_VARS,
	);
	return $t1;
}

sub new_htcc {
	my $t1 = HTML::Template::Compiled::Classic->new_file( $htcc_file,
		#path => 'examples',
		case_sensitive => $CASE_SENSITIVE, # slow down
		loop_context_vars => $LOOP_CONTEXT,
		debug => $debug,
		# note that you have to create the cachedir
		# first, otherwise it will run without cache
        cache_dir => ($FILE_CACHE ? "cache/htc" : undef),
        cache => $MEM_CACHE,
		out_fh => 1,
        global_vars => $GLOBAL_VARS,
        debug => 0,
	);
	return $t1;
}

sub new_tst {
	my $t = Text::ScriptTemplate->new();
	$t->load($tst_file);
	#my $size = total_size($t1);
	#print "size htc = $size\n";
	return $t;
}

sub new_ht {
	my $t2 = HTML::Template->new(
		case_sensitive => $CASE_SENSITIVE, # slow down
		loop_context_vars => $LOOP_CONTEXT,
		#path => 'examples',
		filename => $ht_file,
		cache => $MEM_CACHE,
        $FILE_CACHE ?
        (file_cache => $FILE_CACHE,
        file_cache_dir => 'cache/ht') : (),
        global_vars => $GLOBAL_VARS,
	);
	return $t2;
}

sub new_htj {
	my $t2 = HTML::Template::JIT->new(
		loop_context_vars => 1,
		#path => 'examples',
		filename => $ht_file,
		cache => 1,
		jit_path => 'cache/jit',
        #global_vars => 1,
	);
	return $t2;
}

sub new_tt {
	my $tt= Template->new(
		COMPILE_EXT => '.ttc',
		COMPILE_DIR => 'cache/tt',
		#CACHE_SIZE => 0,
		INCLUDE_PATH => 'examples',
	);
	#my $size = total_size($tt);
	#print "size tt  = $size\n";
	return $tt;
}

sub new_st {
	my $st = Text::ScriptTemplate->new;
	$st->load("examples/template.st");
}

my %params = (
	name => '',
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
open OUT, ">>/dev/null";
#open OUT, ">&STDOUT";

sub output {
	my $t = shift;
	return unless defined $t;
	$params{name} = (ref $t).' '.$count++;
	$t->param(%params);
	#print $t->{code} if exists $t->{code};
	my $out = $t=~m/Compiled/?$t->output(\*OUT):$t->output;
	print OUT $out;
	#print "output():$out\n";
	#my $size = total_size($t);
	#print "size $t = $size\n";
	#print "\nOUT: $out";
}

#open TT_OUT, ">&STDOUT";
sub output_tst {
	my $t = shift;
	return unless defined $t;
	#warn Data::Dumper->Dump([\%params], ['params']);
	$t->setq(%params,tmpl=>$t);
	my $out = $t->fill;
	#print "output_tst():$out\n";
	print OUT $out;
}
sub output_tt {
	my $t = shift;
	return unless defined $t;
	my $filett = $tt_file;
	#$t->process($filett, \%params, \*OUT);
	$t->process($filett, \%params, \*OUT) or die $t->error();
	#my $size = total_size($t);
	#print "size $t = $size\n";
	#print $t->{code} if exists $t->{code};
	#my $out = $t->output;
	#print "\nOUT: $out";
}

my $global_htc = $use{'HTML::Template::Compiled'} ? new_htc : undef;
my $global_htcc = $use{'HTML::Template::Compiled::Classic'} ? new_htcc : undef;
my $global_ht = $use{'HTML::Template'} ? new_ht : undef;
my $global_htj = $use{'HTML::Template::JIT'} ? new_htj : undef;
my $global_tt = $use{'Template'} ? new_tt : undef;
my $global_tst = $use{'Text::ScriptTemplate'} ? new_tst : undef;
if(1) {
timethese ($ARGV[0]||-1, {
        $use{'HTML::Template::Compiled'} ? (
            # deactivate memory cache
            #new_htc_w_clear_cache => sub {my $t = new_htc();$t->clear_cache},
            # normal, with memory cache
            #new_htc => sub {my $t = new_htc()},
            #output_htc => sub {output($global_htc)},
            all_htc => sub {my $t = new_htc();output($t)},
        ) : (),
        $use{'HTML::Template::Compiled::Classic'} ? (
            # deactivate memory cache
            #new_htc_w_clear_cache => sub {my $t = new_htc();$t->clear_cache},
            # normal, with memory cache
            #new_htc => sub {my $t = new_htc()},
            #output_htc => sub {output($global_htc)},
            all_htcc => sub {my $t = new_htcc();output($t)},
        ) : (),
		$use{'HTML::Template'} ? (
			#new_ht => sub {my $t = new_ht()},
			#output_ht => sub {output($global_ht)},
						all_ht => sub {my $t = new_ht();output($t)},
        ) : (),
        $use{'HTML::Template::JIT'} ? (
					#new_htj => sub {my $t = new_htj();},
					#output_htj => sub {output($global_htj)},
						all_htj => sub {my $t = new_htj();output($t)},
        ) : (),
        $use{'Template'} ? (
					#new_tt => sub {my $t = new_tt();},
					#output_tt => sub {output_tt($global_tt)},
						process_tt => sub {output_tt($global_tt)},
#						all_tt_new_object => sub {my $t = new_tt();output_tt($t)},
        ): (),
        $use{'Text::ScriptTemplate'} ? (
					#new_tst => sub {my $t = new_tst();},
                    #output_tst => sub {output_tst($global_tst)},
						all_tst => sub {my $t = new_tst();output_tst($t)},
        ): (),
	});
}
__END__
