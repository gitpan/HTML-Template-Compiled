package HTML::Template::Compiled;
# $Id: Compiled.pm,v 1.85 2005/12/07 14:55:12 tinita Exp $
my $version_pod = <<'=cut';
=pod

=head1 NAME

HTML::Template::Compiled - Template System Compiles HTML::Template files to Perl code

=head1 VERSION

our $VERSION = "0.57";

=cut
# doesn't work with make tardist
#our $VERSION = ($version_pod =~ m/^our \$VERSION = "(\d+(?:\.\d+)+)"/m) ? $1 : "0.01";
our $VERSION = "0.57";
use Data::Dumper;
local $Data::Dumper::Indent = 1; local $Data::Dumper::Sortkeys = 1;
use constant D => 0;
use strict;
use warnings;

use Carp;
use Fcntl qw(:seek :flock);
use File::Spec;
use File::Basename qw(dirname);
use HTML::Template::Compiled::Utils qw(:walkpath);
# TODO
eval {
	require Digest::MD5;
	require HTML::Entities;
	require URI::Escape;
};

use vars qw(
	$__first__ $__last__ $__inner__ $__odd__ $__counter__
	$NEW_CHECK $UNDEF $ENABLE_ASP $ENABLE_SUB
	$CASE_SENSITIVE_DEFAULT $DEBUG_DEFAULT $SEARCHPATH
	%FILESTACK %SUBSTACK
);
$DEBUG_DEFAULT = 0;
$ENABLE_SUB = 0;
$NEW_CHECK = 60 * 10; # 10 minutes default
$UNDEF = ''; # set for debugging
$ENABLE_ASP = 1;
$CASE_SENSITIVE_DEFAULT = 1; # set to 0 for H::T compatibility
$SEARCHPATH = 1;

use constant MTIME => 0;
use constant CHECKED => 1;
use constant LMTIME => 2;
use constant LCHECKED => 3;
use constant TIF => 'IF';
use constant TUNLESS => 'UNLESS';
use constant TELSIF => 'ELSIF';
use constant TELSE => 'ELSE';
use constant T_END => '__EOT__';
use constant TLOOP => 'LOOP';
use constant TWITH => 'WITH';
use constant T_SWITCH => 'SWITCH';
use constant T_CASE => 'CASE';
use constant INDENT => '    ';

my ($start_re,$end_re,$tmpl_re,$close_re,$var_re,$comment_re);
use vars qw($EXPR);
my $asp_re =     ['<%'          ,'%>',    '<%/',          '<%/?.*?%>'];
my $comm_re =    ['<!--\s*TMPL_','\s*-->','<!--\s*/TMPL_','<!--\s*/?TMPL_.*?\s*-->'];
my $classic_re = ['<TMPL_'      ,'>',     '</TMPL_',      '</?TMPL.*?>'];
{
	# TODO
	my $init = 0;
	sub init_re {
		return if $init;
		$start_re = '(?i:' . ($ENABLE_ASP ? "$asp_re->[0]|" : '') . "$classic_re->[0]|$comm_re->[0])";
		$end_re   = '(?:'  . ($ENABLE_ASP ? "$asp_re->[1]|" : '') . "$classic_re->[1]|$comm_re->[1])";
		$tmpl_re  = '(?i:' . ($ENABLE_ASP ? "$asp_re->[3]|" : '') . "$classic_re->[3]|$comm_re->[3])";
		$close_re = '(?i:' . ($ENABLE_ASP ? "$asp_re->[2]|" : '') . "$classic_re->[2]|$comm_re->[2])";
		$var_re = '(?:[\w./]+|->)+';
		$comment_re = '(COMMENT|NOPARSE)\s*(?:\s+(\w+)\s*)?' . $end_re;
		$init = 1;
	}
}

# options / object attributes
use constant PARAM => 0;
{
	my @map = (undef, qw(
		filename file scalar filehandle
	 	cache_dir path cache search_path_on_include
	 	loop_context line_numbers case_sensitive dumper global_vars
	 	method_call deref formatter_path
		debug perl out_fh
		filter formatter
		globalstack
	));
	for my $i (1..@map) {
		my $method = ucfirst $map[$i];
		my $get = sub { return $_[0]->[$i] };
		my $set = sub { $_[0]->[$i] = $_[1] };
		no strict 'refs';
		*{"get$method"} = $get;
		*{"set$method"} = $set;
	}
}

sub new {
	init_re();
	my ($class, %args) = @_;
	my $self = [];
	bless $self, $class;
	$args{path} ||= $ENV{'HTML_TEMPLATE_ROOT'} || '';
	#print "PATH: $args{path}!!\n";
	if ($args{perl}) {
		D && $self->log("new(perl) filename: $args{filename}");
		# we have perl code already!
		$self->init(%args);
		$self->setPerl($args{perl});
		$self->setCache(exists $args{cache}?$args{cache}:1);
		$self->setFilename($args{filename});
		$self->setCache_dir($args{cache_dir});
		$self->setPath($args{path});
		$self->setScalar($args{scalarref});
		unless ($self->getScalar) {
			my $file = $self->createFilename($self->getPath,$self->getFilename);
			$self->setFile($file);
		}
		return $self;
	}
	if (defined $args{filename} or $args{scalarref} or $args{arrayref} or $args{filehandle}) {
		D && $self->log("new()");
		my $t = $self->create(%args);
		return $t;
	}
}

sub create {
	my ($self, %args) = @_;
	#D && $self->log("create(filename=>$args{filename})");
	D && $self->stack;
	if (%args) {
		$self->setCache(exists $args{cache}?$args{cache}:1);
		$self->setCache_dir($args{cache_dir});
		if (defined $args{filename}) {
			$self->setFilename($args{filename});
			D && $self->log("filename: ".$self->getFilename);
			$self->setPath($args{path});
		}
		elsif ($args{scalarref} || $args{arrayref}) {
			$args{scalarref} = \(join '', @{$args{arrayref}}) if $args{arrayref};
			$self->setScalar($args{scalarref});
			my $text = $self->getScalar;
			my $md5 = Digest::MD5::md5_base64($$text);
			D && $self->log("md5: $md5");
			$self->setFilename($md5);
			$self->setPath(defined $args{path} ? $args{path} : '');
		}
		elsif ($args{filehandle}) {
			$self->setFilehandle($args{filehandle});
			$self->setCache(0);
		}
	}
	D && $self->log("trying from_cache()");
	my $t = $self->from_cache();
    if ($t and my $fm = $args{formatter} || $self->getFormatter) {
        #print STDERR "-------------args $fm\n";
        unless ($t->getFormatter) {
			#print STDERR "no t formatter\n";
            $t->setFormatter($fm);
        }
    }
	return $t if $t;
	D && $self->log("tried from_cache()");
	#D && $self->log("tried from_cache() filename=".$self->getFilename);
	# ok, seems we have nothing in cache, so compile
	my $fname = $self->getFilename;
	if (defined $fname and !$self->getScalar and !$self->getFilehandle) {
		#D && $self->log("tried from_cache() filename=".$fname);
		my $file = $self->createFilename($self->getPath,$fname);
		D && $self->log("setFile $file ($fname)");
		$self->setFile($file);
	}
	elsif (defined $fname) {
		$self->setFile($fname);
	}
	$self->init(%args) if %args;
	D && $self->log("compiling... ".$self->getFilename);
	$self->compile();
	return $self;
}
sub from_cache {
	my ($self) = @_;
	my $t;
	D && $self->log("from_cache() filename=".$self->getFilename);
	# try to get memory cache
	if ($self->getCache) {
		$t = $self->from_mem_cache();
		return $t if $t;
	}
	D && $self->log("from_cache() 2 filename=".$self->getFilename);
	# not in memory cache, try file cache
	if ($self->getCache_dir) {
		$t = $self->include();
		return $t if $t;
	}
	D && $self->log("from_cache() 3 filename=".$self->getFilename);
	return;
}

{
	my $cache;
	my $times;
	sub from_mem_cache {
		my ($self) = @_;
		my $dir = $self->getCache_dir;
		$dir = '' unless defined $dir;
		my $fname = $self->getFilename;
		my $cached = $cache->{$dir}->{$fname};
		my $times = $times->{$dir}->{$fname};
		if ($cached && $self->uptodate($times)) {
			return $cached;
		}
		D && $self->log("no or old memcache");
		return;
	}
	sub add_mem_cache {
		my ($self, %times) = @_;
		my $dir = $self->getCache_dir;
		$dir = '' unless defined $dir;
		my $fname = $self->getFilename;
		D && $self->log("add_mem_cache ".$fname);
		my $clone = $self->clone;
		$clone->clear_params();
		$cache->{$dir}->{$fname} = $clone;
		$times->{$dir}->{$fname} = \%times;
	}
	sub clear_cache {
		my $dir = $_[0]->getCache_dir;
		# clear the whole cache
		$cache = {}, $times = {}, return unless defined $dir;
		# only specific directory
		$cache->{$dir} = {};
		$times->{$dir} = {};
	}
	sub clear_filecache {
		my ($self, $dir) = @_;
		defined $dir or
			$dir = $self->getCache_dir;
		return unless -d $dir;
		ref $self and $self->lock;
		opendir my $dh, $dir or die "Could not open '$dir': $!";
		my @files = grep { m/\.pl$/ } readdir $dh;
		for my $file (@files) {
			my $file = File::Spec->catfile($dir, $file);
			unlink $file or die "Could not delete '$file': $!";
		}
		ref $self and $self->unlock;
		return 1;
	}
}



sub compile {
	my ($self) = @_;
	my ($source, $compiled);
	if (my $file = $self->getFile and !$self->getScalar) {
		# thanks to sam tregars testsuite
		# don't recursively include
		my $recursed = ++$FILESTACK{$file};
		D && $self->log("compile from file ".$file);
		die "Could not open '$file': $!" unless -f $file;
		my @times = $self->_checktimes($file);
		my $text = $self->_readfile($file);
		die "HTML::Template: recursive include of "
			. $file . " $recursed times" if $recursed > 10;
		my ($source,$compiled) = $self->_compile($text,$file);
		--$FILESTACK{$file} or delete $FILESTACK{$file};
		$self->setPerl($compiled);
		$self->getCache and $self->add_mem_cache(
			checked => time,
			mtime => $times[MTIME],
		);
		D && $self->log("compiled $file");
		if ($self->getCache_dir) {
			D && $self->log("add_file_cache($file)");
			$self->add_file_cache($source,
				checked => time,
				mtime => $times[MTIME],
			);
		}
	}
	elsif (my $text = $self->getScalar) {
		my $md5 = $self->getFilename; # yeah, weird
		D && $self->log("compiled $md5");
		my ($source,$compiled) = $self->_compile($$text,$md5);
		$self->setPerl($compiled);
		if ($self->getCache_dir) {
			D && $self->log("add_file_cache($file)");
			$self->add_file_cache($source,
				checked => time,
				mtime => time,
			);
		}
	}
	elsif (my $fh = $self->getFilehandle) {
		local $/;
		my $data = <$fh>;
		my ($source,$compiled) = $self->_compile($data,'');
		$self->setPerl($compiled);
		
	}
}
sub add_file_cache {
	my ($self, $source, %times) = @_;
	$self->lock;
	my $cache = $self->getCache_dir;
	my $plfile = $self->escape_filename($self->getFile);
	my $filename = $self->getFilename;
	my $lmtime = localtime $times{mtime};
	my $lchecked = localtime $times{checked};
	D && $self->log("add_file_cache() $cache/$plfile");
	open my $fh, ">$cache/$plfile.pl" or die $!; # TODO File::Spec
	my $path = $self->getPath;
	my $path_str = '['.
    ( ref $path eq 'ARRAY'
		? (join ', ', map { $self->quote_file($_) } @$path)
		: $self->quote_file($path))
    . ']';
	my $isScalar = $self->getScalar ? 1 : 0;
	my $file_args = $isScalar
		? <<"EOM"
        scalarref => $isScalar,
        filename => '@{[$self->getFilename]}',
EOM
		: <<"EOM";
        filename => '@{[$self->getFilename]}',
        file => '@{[$self->getFile]}',
EOM
	print $fh <<"EOM";
		package HTML::Template::Compiled;
# file date $lmtime
# last checked date $lchecked
my \$args = {
	times => {
		mtime => $times{mtime},
		checked => $times{checked},
	},
	htc => {
		case_sensitive => @{[$self->getCase_sensitive]},
		cache_dir => '$cache',
$file_args
		#filename => '@{[$self->getFilename]}',
		#file => '@{[$self->getFile]}',
		#scalarref => $isScalar,
		path => $path_str,
		method_call => '@{[$self->getMethod_call]}',
		deref => '@{[$self->getDeref]}',
		out_fh => @{[$self->getOut_fh]},
		# TODO
		# dumper => ...
		# template subroutine
		perl => $source,
	},
};
EOM
	D && $self->log("$cache/$plfile.pl generated");
	$self->unlock;
}

sub include {
	my ($self) = @_;
	D && $self->stack;
	my $file = $self->createFilename($self->getPath,$self->getFilename);
	D && $self->log("include file: $file");
	#$self->setFile($file);
	my $dir = $self->getCache_dir;
	my $escaped = $self->escape_filename($file);
	my $req = File::Spec->catfile($dir, "$escaped.pl");
	return unless -f $req;
	return $self->include_file($req);
}

sub include_file {
	my ($self, $req) = @_;
	D && $self->log("do $req");
	my $r = do "$req";
	my $args = $r->{htc};
	my $t = HTML::Template::Compiled->new(%$args);
	D && $self->log("include",$t,"$args->{perl}");
	return unless $t->uptodate($r->{times});
	$t->add_mem_cache(
		checked=>$r->{times}->{checked},
		mtime => $r->{times}->{mtime},
	);
	return $t;
}

sub createFilename {
	my ($self,$path,$filename) = @_;
	D && $self->log("createFilename($path,$filename)");
	D && $self->stack(1);
	if (!length $path or File::Spec->file_name_is_absolute($filename)) {
		return $filename;
	}
	else {
		D && $self->log("file: ".File::Spec->catfile($path, $filename));
		my $sp = $self->getSearch_path_on_include;
		for (ref $path
		   	? $sp
			? @$path
			: $path->[0]
		   	: $path) {
			my $fp = File::Spec->catfile($_, $filename);
			return $fp if -f $fp;
		}
		# TODO - bug with scalarref
		croak "'$filename' not found";
	}
}

sub uptodate {
	my ($self, $times) = @_;
	return 1 if $self->getScalar;
	my $now = time;
	if ($now - $times->{checked} < $NEW_CHECK) {
		return 1;
	}
	else {
		my $file = $self->createFilename($self->getPath,$self->getFilename);
		$self->setFile($file);
		#print STDERR "uptodate($file)\n";
		my @times = $self->_checktimes($file);
		if ($times[MTIME] <= $times->{mtime}) {
			D && $self->log("uptodate template old");
			$times->{checked} = $now;
			return 1;
		}
	}
	return 0;
}

sub dump {
	my ($self, $var) = @_;
	if (my $sub = $self->getDumper()) {
		unless (ref $sub) {
			# we have a plugin
			$sub =~ tr/0-9a-zA-Z//cd; # allow only words
			my $class = "HTML::Template::Compiled::Plugin::$sub";
			$sub = \&{$class . '::dumper'};
		}
		return $sub->($var);
	}
	else {
		require Data::Dumper;
		local $Data::Dumper::Indent = 1; local $Data::Dumper::Sortkeys = 1;
		return Data::Dumper->Dump([$var],['DUMP']);
	}
}

sub init {
	my ($self, %args) = @_;
	my %defaults = (
		# defaults
		method_call => '->',
		deref => '.',
		formatter_path => '/',
		search_path_on_include => $SEARCHPATH,
		line_numbers => 0,
		loop_context_vars => 0,
		case_sensitive => $CASE_SENSITIVE_DEFAULT,,
		debug => $DEBUG_DEFAULT,
		out_fh => 0,
		global_vars => 0,
		%args,
	);
	$self->setMethod_call($defaults{method_call});
	$self->setDeref($defaults{deref});
	$self->setLine_numbers(1) if $args{line_numbers};
	$self->setLoop_context(1) if $args{loop_context_vars};
	$self->setCase_sensitive($defaults{case_sensitive});
	$self->setDumper($args{dumper}) if $args{dumper};
	$self->setFormatter($args{formatter}) if $args{formatter};
	$self->setSearch_path_on_include($defaults{search_path_on_include});
	if ($args{filter}) {
		require HTML::Template::Compiled::Filter;
		$self->setFilter(HTML::Template::Compiled::Filter->new($args{filter}));
	}
	$self->setDebug($defaults{debug});
	$self->setOut_fh($defaults{out_fh});
	$self->setGlobal_vars($defaults{global_vars});
	$self->setFormatter_path($defaults{formatter_path});
}

sub _readfile {
	my ($self, $file) = @_;
	open my $fh, $file or die "Cannot open '$file': $!";
	local $/;
	my $text = <$fh>;
	return $text;
}

sub _compile {
	my ($self, $text, $fname) = @_;
	D && $self->log("_compile($fname)");
	if (my $filter = $self->getFilter) {
		$filter->filter($text);
	}
	if ($self->getLine_numbers) {
		# split lines and preserve empty trailing lines
		my @lines = split /\n/, $text, -1;
		for my $i (0..$#lines) {
			$lines[$i] =~ s#($tmpl_re)#__${i}__$1#g;
		}
		$text = join "\n", @lines;
	}
	my $re = $self->getLine_numbers? qr#((?:__\d+__)?$tmpl_re)# : qr#($tmpl_re)#;
	my @p = split $re, $text;
	my $level = 1;
	my $code = '';
	my $stack = [T_END];

	# got this trick from perlmonks.org
	my $anon = D || $self->getDebug ? qq{local *__ANON__ = "htc_$fname";\n} : '';

	no warnings 'uninitialized';
	my $output = '$OUT .= ';
	my $out_fh = $self->getOut_fh;
	if ($out_fh) {
		$output = 'print $OFH ';
	}
	my $header = <<"EOM";
sub {
	no warnings;
$anon
	my (\$t, \$P, \$C, \$OFH) = \@_;
	my \$OUT;
    #my \$C = \\\$P;
EOM

	my $line = 0;
	my @lexicals;
	my @switches;
	my $comment = 0;
	my $noparse = 0;
	for (@p) {
		my $indent = INDENT x $level;
		s/~/\\~/g;
		if ($self->getLine_numbers && s#__(\d+)__($tmpl_re)#$2#) {
			$line = $1+1;
		}
		my $meth = $self->getMethod_call;
		my $deref = $self->getDeref;
		my $format = $self->getFormatter_path;
		my %var_args = (
			deref => $deref,
			method_call => $meth,
			formatter_path => $format,
			lexicals => \@lexicals,
		);
		# --------- TMPL_VAR
		if (!$comment && !$noparse) {
			if (m#$start_re(VAR|=)\s+(?:NAME=)?(['"]?)($var_re)\2.*$end_re#i) {
				my $type = uc $1;
				$type = "VAR" if $type eq '=';
				my $var = $3;
				my $escape = '';
				if (m/\s+ESCAPE=(['"]?)(\w+(?:\|\w+)*)\1/i) {
					$escape = $2;
				}
				my $default;
				if (($default)=m/\s+DEFAULT=('([^']*)'|"([^"]*)"|(\S+))/i) {
					$default =~ s/^['"]//;
					$default =~ s/['"]$//;
					$default =~ s/'/\\'/g;
				}
				my $varstr = $self->_make_path(
					%var_args,
					var => $var,
					final => 1,
				);
				#print "line: $_ var: $var\n";
				my $root = 0;
				my $path = 0;
				if ($var =~ s/^\.//) {
					# we have NAME=.ROOT
					$root++;
				}
				if ($var =~ tr/.//) {
					# we have NAME=BLAH.BLUBB
					$path++;
				}
				if ($root || $path) {
					$code .= qq#${indent}\{\n${indent}  my \$C = \$C;\n#;
				}
				if ($root) {
					$code .= qq#${indent}  \$C = \\\$P;\n#;
				}
				if (defined $default) {
					$varstr = qq#defined $varstr ? $varstr : '$default'#;
				}
				if (uc $type eq 'VAR') {
					if ($escape) {
						$escape = uc $escape;
						my @escapes = split m/\|/, $escape;
						for (@escapes) {
							if ($_ eq 'HTML') {
								$varstr = qq#\$t->escape_html($varstr)#;
							}
							elsif ($_ eq 'URL') {
								$varstr = qq#\$t->escape_uri($varstr)#;
							}
							elsif ($_ eq 'DUMP') {
								$varstr = qq#\$t->dump($varstr)#;
							}
						}
						$code .= qq#${indent}$output $varstr;\n#;
					}
					else {
						#$code .= qq#print STDERR "<<<<<<<<<<< $var\\n";\n\# line 1000\n#;
						$code .= qq#${indent}$output $varstr;\n#;
					}
				}
				if ($root || $path) {
					$code .= qq#\n${indent}\}\n#;
				}
			}

			# --------- TMPL_WITH
			elsif (m#${start_re}WITH\s+(?:NAME=)?(['"]?)($var_re)\1\s*$end_re#i) {
				push @$stack, TWITH;
				$level++;
				my $var = $2;
				my $varstr = $self->_make_path(
					%var_args,
					var => $var,
					final => 0,
				);
				$code .= qq#${indent}\{ \# WITH $var\n#;
				$code .= qq#${indent}  my \$C = \\$varstr;\n#;
			}

			# --------- TMPL_LOOP
			elsif (m{ $start_re
					(?:LOOP|FOR) \s+
					(?:NAME=)?
					(['"]?)   # $1 "'
					($var_re) # $2
					\1
					(?: \s+ AS \s+ (\w+) ) ? # $3
					\s* $end_re }ix) {
				push @$stack, TLOOP;
				my $var = $2;
				my $lexical = $3;
				push @lexicals, $lexical;
				my $lexi = defined $lexical ? "${indent}my \$$lexical = \$\$C;\n" : "";
				my $varstr = $self->_make_path(
					%var_args,
					var => $var,
					final => 0,
				);
			$level+=2;
			my $ind = INDENT;
			my $global = $self->getGlobal_vars ? <<"EOM" : '';
${indent}my \$stack = \$t->getGlobalstack;
${indent}push \@\$stack, \$\$C;
${indent}\$t->setGlobalstack(\$stack);
EOM
			$code .= <<"EOM";
${indent}if (UNIVERSAL::isa(my \$array = $varstr, 'ARRAY') )\{
${indent}${ind}my \$size = \$#{ \$array };
$global

${indent}${ind}# loop over $var
${indent}${ind}for my \$ix (\$[..\$size) {
${indent}${ind}${ind}my \$C = \\ (\$array->[\$ix]);
$lexi
EOM
				if ($self->getLoop_context) {
					my $indent = INDENT x $level;
					$code .= <<"EOM";
${indent}local \$__counter__ = \$ix+1;
${indent}local \$__first__   = \$ix == \$[;
${indent}local \$__last__    = \$ix == \$size;
${indent}local \$__odd__     = !(\$ix & 1);
${indent}local \$__inner__   = !\$__first__ && !\$__last__;
EOM
				}
			}

			# --------- TMPL_ELSE
			elsif (m#${start_re}ELSE\s*$end_re#i) {
				# we can only have an open if or unless
				$self->_checkstack($fname,$line,$stack, TELSE);
				my $indent = INDENT x ($level-1);
				$code .= qq#${indent}\}\n${indent}else {\n#;
			}

			# --------- / TMPL_IF TMPL UNLESS TMPL_WITH
			elsif (m#$close_re(IF|UNLESS|WITH)(?:\s+$var_re)?\s*$end_re#i) {
				$self->_checkstack($fname,$line,$stack, uc "$1");
				pop @$stack;
				$level--;
				my $indent = INDENT x $level;
				$code .= qq#${indent}\} \# end $1\n#;
			}

			# --------- / TMPL_LOOP
			elsif (m{ $close_re
				(?:LOOP|FOR) (?:\s*$var_re\s*)?
				\s* $end_re}ix) {
				$self->_checkstack($fname,$line,$stack, TLOOP);
				pop @$stack;
				pop @lexicals;
				$level--;
				$level--;
				my $indent = INDENT x $level;
				my $global = $self->getGlobal_vars ? <<"EOM" : '';
${indent}my \$stack = \$t->getGlobalstack;
${indent}pop \@\$stack;
${indent}\$t->setGlobalstack(\$stack);
EOM
				$code .= <<"EOM";
${indent}@{[INDENT()]}\}
${indent}\} # end loop
$global
EOM
			}
			# --------- TMPL_IF TMPL UNLESS TMPL_ELSE
			elsif (m#$start_re(ELSIF|IF|UNLESS)\s+(DEFINED\s+)?(?:NAME=)?(['"]?)($var_re)\3\s*$end_re#i) {
				my $type = uc $1;
				my $def = $2;
				my $var = $4;
				my $indent = INDENT x $level;
				my $varstr = $self->_make_path(
					%var_args,
					var => $var,
					final => 1,
				);
				my $if = {IF => 'if', UNLESS => 'unless', ELSIF => 'elsif'}->{uc $1};
				my $elsif = $type eq 'ELSIF' ? 1 : 0;
				if ($def) {
					$varstr = "defined( $varstr )";
				}
				if ($elsif) {
					$code .= qq#${indent}\}\n#;
					$self->_checkstack($fname,$line,$stack, TELSIF);
				}
				else {
					push @$stack, $type;
					$level++;
				}
				$code .= <<"EOM"
${indent}$if($varstr) \{
EOM
			}
			elsif (m# $start_re SWITCH \s+ (?:NAME=)?(['"]?)($var_re)\1\s* $end_re #xi) {
				my $var = $2;
				push @$stack, T_SWITCH;
				push @switches, 0;
				$level++;
				my $varstr = $self->_make_path(
					%var_args,
					var => $var,
					final => 0,
				);
				$code .= <<"EOM";
${indent}SWITCH: for my \$_switch ($varstr) \{
EOM
			}
			elsif (m# $close_re SWITCH (?:\s+$var_re)?\s*$end_re#xi) {
				$self->_checkstack($fname,$line,$stack, T_SWITCH);
				pop @$stack;
				$level--;
				if ($switches[$#switches]) {
					# we had at least one CASE, so we close the last if
					$code .= qq#${indent}\} \# last case\n#;
				}
				$code .= qq#${indent}\}\n#;
				pop @switches;
			}
			elsif (m# $start_re CASE (\s+\w+(?:,\s*\w+)?)? \s* $end_re #xi) {
				my $val = $1;
				$val =~ s/^\s+//;
				$self->_checkstack($fname,$line,$stack, T_CASE);
				if ($switches[$#switches]) {
					# we aren't the first case
					$code .= qq#${indent}last SWITCH;\n${indent}\}\n#;
				}
				else {
					$switches[$#switches] = 1;
					$level++;
				}
				if (!length $val or uc $val eq 'DEFAULT') {
					$code .= qq#${indent}if (1) \{\n#;
				}
				else {
					my $values = join ",", map { qq#'$_'# } split ",", $val;
					$code .= qq#${indent}if (grep \{ \$_switch eq \$_ \} $values) \{\n#;
				}
			}
			elsif (m# $start_re INCLUDE\s+(.+?) $end_re #ixs) {
				my $match = $1;
				my $filename;
				my $varstr;
				my $path = $self->getPath();
				my $dir;
				$path = [$path] unless ref $path eq 'ARRAY';
				if ($match =~ m/(?:VAR=)(['"]?)($var_re)\1/i) {
					# dynamic filename
					my $dfilename = $2;
					$varstr = $self->_make_path(
						%var_args,
						var => $dfilename,
						final => 0,
					);
				}
				elsif ($match =~ m/(?:NAME=)?(['"]?)([^'">]+)\1/i) {
					# static filename
					$filename = $2;
					$varstr = $self->quote_file($filename);
					$dir = dirname $fname;
					if (defined $dir and !grep { $dir eq $_ } @$path) {
						# add the current directory to top of paths
						$path = [$dir, @$path]; # create new $path, don't alter original ref
					}
					# generate included template
					{
						D && $self->log("compile include $filename!!");
						my $cached_or_new = $self->clone_init($path, $filename, $self->getCache_dir);
					}
				}
				#print STDERR "include $varstr\n";
				my $cache = $self->getCache_dir;
				$path = defined $path
					? !ref $path
						? $self->quote_file($path)
						# support path => arrayref soon
						: '['.join(',',map { $self->quote_file($_) } @$path).']'
					: 'undef';
				$cache = defined $cache ? $self->quote_file($cache) : 'undef';
				$code .= <<"EOM";
${indent}\{
${indent}  my \$new = \$t->clone_init($path,$varstr,$cache);
${indent}  $output \$new->getPerl()->(\$new,\$P,\$C@{[$out_fh ? ",\$OFH" : '']});
${indent}\}
EOM

			}
			elsif (m#$start_re$comment_re#i) {
				my $name = $2;
				uc $1 eq 'COMMENT' ? $comment++ : $noparse++;
				$code .= qq{ # comment $name (level $comment)\n};
			}
			elsif (m#$close_re$comment_re#i) {
				my $name = $2;
				$code .= qq{ # end comment $name (level $comment)\n};
				uc $1 eq 'COMMENT' ? $comment-- : $noparse--;
			}
			else {
				if (length $_) {
					s/\\/\\\\/g;
					s/'/\\'/g;
					$code .= qq#$indent$output '$_';\n#;
				}
			}
		}
		else {
			if (m#$start_re$comment_re#i) {
				my $name = $2;
				uc $1 eq 'COMMENT' ? $comment++ : $noparse++;
				$code .= qq{ # comment $name (level $comment)\n};
			}
			elsif (m#$close_re$comment_re#i) {
				my $name = $2;
				$code .= qq{ # end comment $name (level $comment)\n};
				uc $1 eq 'COMMENT' ? $comment-- : $noparse--;
			}
			else {
				# don't output anything if we are in a comment
				# but output if we are in noparse
				if (!$comment && length $_) {
					s/\\/\\\\/g;
					s/'/\\'/g;
					$code .= qq#$indent$output '$_';\n#;
				}
			}
		}
	}
	$self->_checkstack($fname,$line,$stack, T_END);
	$code = $header . $code . "\n} # end of sub\n";
	#$code .= "\n} # end of sub\n";
	print STDERR "# ----- code \n$code\n# end code\n" if $self->getDebug;
	my $sub = eval $code;
	die "code: $@" if $@;
	return $code, $sub;
	
}

sub quote_file {
	my $f = $_[1];
	$f =~ s/'/\\'/g;
	return qq/'$f'/;
}

sub _make_path {
	my ($self, %args) = @_;
	my $lexicals = $args{lexicals};
	if (grep { defined $_ && $args{var} eq $_ } @$lexicals) {
		return "\$$args{var}";
	}
	my $root = 0;
	if ($args{var} =~ m/^__(\w+)__$/) {
		return "\$\L$args{var}\E";
	}
	if ($args{var} =~ s/^_//) {
		$root = 0;
	}
	elsif ($args{var} =~ m/^(?:\Q$args{deref}\E|\Q$args{method_call}\E|\Q$args{formatter_path}\E)/) {
		$root = 1;
	}
	my @split = split m/(?=\Q$args{deref}\E|\Q$args{method_call}\E|\Q$args{formatter_path}\E)/, $args{var};
	my @paths;
	for my $p (@split) {
		if ($p =~ s/^\Q$args{method_call}//) {
			push @paths, '['.PATH_METHOD.",'$p']";
		}
		elsif ($p =~ s/^\Q$args{deref}//) {
			push @paths, '['.PATH_DEREF.",'".($self->getCase_sensitive?$p:uc$p)."']";
		}
		elsif ($p =~ s/^\Q$args{formatter_path}//) {
			push @paths, '['.PATH_FORMATTER.",'".($self->getCase_sensitive?$p:uc$p)."']";
		}
		else {
			push @paths, '['.PATH_DEREF.", '".($self->getCase_sensitive?$p:uc$p)."']";
		}
	}
	local $" = ",";
	my $final = $args{final} ? 1 : 0;
	my $getvar = $ENABLE_SUB ? '_get_var_sub' : '_get_var';
	$getvar .= $self->getGlobal_vars ? '_global' : '';
	my $varstr = "\$t->$getvar(\$P," .($root?'$P':'$$C').",$final,@paths)";
	return $varstr;
	return ($root, \@paths);
}


# -------- warning, ugly code
# i'm trading maintainability for efficiency here

sub try_global {
	my ($self, $walk, $path) = @_;
	my $stack = $self->getGlobalstack||[];
	for my $item ($walk, reverse @$stack) {
		next unless exists $item->{$path};
		return $item->{$path};
	}
	return $walk;
}

{
	# ----------- still ugly code
	# generating different code depending on global_vars
	my $code = <<'EOM';
sub {
	my ($self, $P, $ref, $final, @paths) = @_;
	my $walk = $ref;
	for my $path (@paths) {
        last unless defined $walk;
		#print STDERR "ref: $walk, key: $key\n";
		if ($path->[0] == PATH_DEREF) {
			if (ref $walk eq 'ARRAY') {
				$walk = $walk->[$path->[1]];
			}
			else {
*** walk ***
			}
		}
		elsif ($path->[0] == PATH_METHOD) {
			my $key = $path->[1];
			$walk = $walk->$key;
		}
		elsif ($path->[0] == PATH_FORMATTER) {
			my $key = $path->[1];
			my $sub = $self->getFormatter()->{ref $walk}->{$key};
			$walk = defined $sub
				? $sub->($walk)
				: $walk->{$key};
		}
	}
	return $walk;
}
EOM
	my $global = <<'EOM';
	$walk = $self->try_global($walk, $path->[1]);
EOM
	my $walk = <<'EOM';
	$walk = $walk->{$path->[1]};
EOM
	my $sub = $code;
	$sub =~ s/^\Q*** walk ***\E$/$walk/m;
	my $subref = eval $sub;
	no strict 'refs';
	*{'HTML::Template::Compiled::_get_var'} = $subref;
	$sub = $code;
	$sub =~ s/^\Q*** walk ***\E$/$global/m;
	$subref = eval $sub;
	*{'_get_var_global'} = $subref;
}

# and another two ugly subroutines

sub _get_var_sub {
	my ($self, $P, $ref, $final, @paths) = @_;
	my $var = $self->_get_var($P, $ref, $final, @paths);
	if ($ENABLE_SUB and $final and ref $var eq 'CODE') {
		return $var->();
	}
	return $var;
}
sub _get_var_sub_global {
	my ($self, $P, $ref, $final, @paths) = @_;
	my $var = $self->_get_var_global($P, $ref, $final, @paths);
	if ($ENABLE_SUB and $final and ref $var eq 'CODE') {
		return $var->();
	}
	return $var;
}

# end ugly code, phooey

{
	my %map = (
		IF => [TIF,TUNLESS],
		UNLESS => [TUNLESS],
		ELSIF => [TIF,TUNLESS],
		ELSE => [TIF,TUNLESS,TELSIF],
		LOOP => [TLOOP],
		WITH => [TWITH],
		T_SWITCH() => [T_SWITCH],
		T_CASE() => [T_SWITCH],
		T_END() => [T_END],
	);
	sub _checkstack {
		my ($self, $fname,$line, $stack, $check) = @_;
		# $self->stack(1);
		my @allowed = @{ $map{$check} };
		return 1 if @$stack == 0 and @allowed == 0;
		die "Closing tag 'TMPL_$check' does not have opening tag at $fname line $line\n" unless @$stack;
		if ($allowed[0] eq T_END and $stack->[-1] ne T_END) {
			# we hit the end of the template but still have an opening tag to close
			die "Missing closing tag for '$stack->[-1]' at end of $fname line $line\n";
		}
		for (@allowed) {
			return 1 if $_ eq $stack->[-1];
		}
		croak "'TMPL_$check' does not match opening tag ($stack->[-1]) at $fname line $line\n";
	}
}
sub escape_filename {
	my ($t, $f) = @_;
	$f =~ s#([/:\\])#'%'.uc sprintf"%02x",ord $1#ge;
	return $f;
}

sub cache {
}


sub _checktimes {
	my $self = shift;
	D && $self->stack;
	my $filename = shift;
	my $mtime = (stat $filename)[9];
	#print STDERR "stat $filename = $mtime\n";
	my $checked = time;
	my $lmtime = localtime $mtime;
	my $lchecked = localtime $checked;
	return ($mtime, $checked, $lmtime, $lchecked);
}

sub clone {
	my ($self) = @_;
	return bless [@$self], ref $self;
}
sub clone_init {
	my ($self, $path,$filename,$cache) = @_;
	my $new = bless [@$self], ref $self;
	D && $self->log("clone_init($path,$filename,$cache)");
	$new->setFilename($filename);
	$new->setScalar();
	$new->setFilehandle();
	$new->setPath($path);
	$new = $new->create();
	$new;
}

sub preload {
	my ($class, $dir) = @_;
	opendir my $dh, $dir or die "Could not open '$dir': $!";
	my @files = grep { m/\.pl$/ } readdir $dh;
	closedir $dh;
	for my $file (@files) {
		$class->include_file(File::Spec->catfile($dir, $file));
	}
}

sub clear_params {
	$_[0]->[PARAM] = ();
}
sub param {
	my $self = shift;
	unless (@_) {
		return UNIVERSAL::can($self->[PARAM],'can') ?
			$self->[PARAM] :
			$self->[PARAM] ?
				keys %{$self->[PARAM]} :
				();
	}
	if (@_ == 1) {
		if (ref $_[0]) {
			# feed a hashref or object
			$self->[PARAM] = $_[0];
			return;
		}
		else {
			# query a parameter
			return $self->[PARAM]->{$_[0]};
		}
	}
	my %p = @_;
	if (!$self->getCase_sensitive) {
		my $uc = $self->uchash({%p});
		%p = %$uc;
	}
	$self->[PARAM]->{$_} = $p{$_} for keys %p;
}

sub uchash {
	my ($self, $data) = @_;
	my $uc;
	if (ref $data eq 'HASH') {
		for my $key (keys %$data) {
			my $uc_key = uc $key;
			my $val = $self->uchash($data->{$key});
			$uc->{$uc_key} = $val;
		}
	}
	elsif (ref $data eq 'ARRAY') {
		for my $item (@$data) {
			my $new = $self->uchash($item);
			push @$uc, $new;
		}
	}
	else {
		$uc = $data;
	}
	return $uc;
}

sub output {
	my ($self, $fh) = @_;
	my %p = %{$self->[PARAM]||{}};
	my $f = $self->getFile;
	$fh = \*STDOUT unless $fh;
	$self->getPerl()->($self,\%p,\\%p,$fh);
}

sub import {
	my ($class, %args) = @_;
	if ($args{compatible}) {
		$ENABLE_SUB = 1;
		$CASE_SENSITIVE_DEFAULT = 0;
		$SEARCHPATH = 0;
	}
}

{
my $lock_fh;
	sub lock {
		my $file = File::Spec->catfile($_[0]->getCache_dir, "lock");
		unless (-f $file) {
			# touch
			open $lock_fh, '>', $file;
			close $lock_fh;
		}
		open $lock_fh, '+<', $file;
		flock $lock_fh, LOCK_EX;
	}
	sub unlock {
		close $lock_fh;
	}
}

sub escape_html {
	my ($self, $var) = @_;
	my $new = $var;
	# we have to do this cause HTML::Entities changes its arg
	# doesn't do that in the latest version and i'm not sure
	# how it behaved before
	HTML::Entities::encode_entities($new);
	return $new;
}
sub escape_uri {
	return URI::Escape::uri_escape($_[1]);
}

sub __test_version {
	my $v = __PACKAGE__->VERSION;
	return 1 if $version_pod =~ m/VERSION.*\Q$v/;
	return;
}

sub stack {
	my ($self,$force) = @_;
	return if !D and !$force;
	my $i = 0;
	my $out;
	while(my @c = caller($i)) {
		$out .= "$i\t$c[0] l. $c[2] $c[3]\n";
		$i++;
	}
	print STDERR $out;
}
sub log {
	#return unless D;
	my ($self, @msg) = @_;
	my @c = caller();
	my @c2 = caller(1);
	print STDERR "----------- ($c[0] line $c[2] $c2[3])\n";
	for (@msg) {
		if (!defined $_) {
			print STDERR "---  UNDEF\n";
		}
		elsif (!ref $_) {
			print STDERR "--- $_\n";
		}
		else {
			if (ref $_ eq __PACKAGE__) {
				print STDERR "DUMP HTC\n";
				for my $m (qw(file perl)) {
					my $s = "get".ucfirst$m;
					print STDERR "\t$m:\t",$_->$s||"UNDEF","\n";
				}
			}
			else {
				print STDERR "--- DUMP ---: ".Dumper $_;
			}
		}
	}
}



1;

__END__

=head1 SYNOPSIS

  use HTML::Template::Compiled;
  my $htc = HTML::Template::Compiled->new(filename => 'test.tmpl');
  $htc->param(
    BAND => $name,
    ALBUMS = [
      { TITLE => $t1, YEAR => $y1 },
      { TITLE => $t2, YEAR => $y2 },
    ],
  );
  print $htc->output;

  test.tmpl:
  Band: <TMPL_VAR BAND>
  <TMPL_LOOP ALBUMS>
  Title: <TMPL_VAR TITLE> (<TMPL_VAR YEAR>)
  </TMPL_LOOP>

=head1 DESCRIPTION

HTML::Template::Compiled (HTC) is a template system which uses the same
template syntax as HTML::Template and the same perl API. Internally
it works different, because it turns the template into perl code,
and once that is done, generating the output is much faster than with
HTML::Template (4-5 times at the moment, at least with my tests). It also
can generate perl files so that the next time the template is loaded it
doesn't have to be parsed again. The best performance gain is probably
reached in applications running under mod_perl, for example.

If you don't use caching at all, HTC will be even slower than H::T (but still a
bit faster than Template-Toolkit. See the C<examples/bench.pl>.

HTC will use a lot of memory because it keeps all template objects in memory.
If you are on mod_perl, and have a lot of templates, you should preload them at server
startup to be sure that it is in shared memory. At the moment HTC is not tested for
keeping all data in shared memory (e.g. when a copy-on-write occurs), but i'll test
that soon. For preloading you can now use
  HTML::Template::Compiled->preload($dir).

HTC does not implement all features of HTML::Template (yet), and
it has got some additional features which are explained below.

HTC will complain if you have a closing tag that does not fit
the last opening tag. To get the line number, set the line_numbers-option
(See L<"OPTIONS"> below)

NOTE: If you don't need any of the additional features listed below and if you don't
need the speed (in many cases it's probably not worth trading speed for memory), then
you might be better off with just using HTML::Template.

NOTE2: If you have any questions, bug reports, send them to me and not to Sam Tregar.
This module is developed by me at the moment, independently from HTML::Template, although
I try to get most of the tests from it passing for HTC. See L<"RESOURCES"> for
current information.

=head2 FEATURES FROM HTML::TEMPLATE

=over 4

=item TMPL_VAR

=item TMPL_LOOP

=item TMPL_(IF|UNLESS|ELSE)

=item TMPL_INCLUDE

=item HTML_TEMPLATE_ROOT

=item ESCAPE=(HTML|URL)

=item DEFAULT=...

=item C<__first__>, C<__last__>, C<__inner__>, C<__odd__>, C<__counter__>

=item <!-- TMPL_VAR NAME=PARAM1 -->

=item case insensitive var names

use option case_sensitive => 0 to use this feature

=item filters

=item vars that are subrefs

=item scalarref, arrayref, filehandle

=item C<global_vars>

new (roughly tested)

=back

=head2 ADDITIONAL FEATURES

=over 4

=item TMPL_ELSIF

=item TMPL_WITH

=item TMPL_COMMENT

see L<"TMPL_COMMENT">

=item TMPL_NOPARSE

see L<"TMPL_NOPARSE">

=item TMPL_SWITCH, TMPL_CASE

see L<"TMPL_SWITCH">

=item Generating perl code

=item more variable access

see L<"VARIABLE ACCESS">

=item rendering objcets

see L<"RENDERING OBJECTS">

=item output to filehandle

=item Dynamic includes

see L<"INCLUDE">

=item TMPL_IF DEFINED

Check for definedness instead of truth:
  <TMPL_IF DEFINED NAME="var">

=item asp/jsp-like templates

For those who like it (i like it because it is shorter than TMPL_), you
can use E<lt>% %E<gt> tags and the E<lt>%= tag instead of E<lt>%VAR (which will work, too):

 <%IF blah%>  <%= VARIABLE%>  <%/IF%>

=back

=head2 MISSING FEATURES

There are some features of H::T that are missing and that I don't plan
to implement. I'll try to list them here.

=over 4

=item C<die_on_bad_params>

I don't think I'll implement that in the near future.

=back

=head2 DIFFERENT DEFAULTS


At the moment there are three defaults that differ from L<HTML::Template>:

=over 4

=item case_sensitive

default is 1. Set it via C<$HTML::Template::Compiled::CASE_SENSITIVE_DEFAULT = 0>
Note (again): this will slow down templating a lot.

=item subref variables

default is 0. Set it via C<$HTML::Template::Compiled::ENABLE_SUB = 1>

=item search_path_on_include

default is 1. Set it via C<$HTML::Template::Compiled::SEARCHPATH = 0>

=back

To be compatible with all use:

  use HTML::Template::Compiled compatible => 1;

=head2 ESCAPING

Like in HTML::Template, you have C<ESCAPE=HTML> and C<ESCAPE=URL>. (C<ESCAPE=1> will follow.)
Additionally you have C<ESCAPE=DUMP>, which by default will generate a Data::Dumper output.
You can change that output by setting a different dumper function, see L<"OPTIONS"> dumper.

You can also chain different escapings, like C<ESCAPE=DUMP|HTML>.

=head2 INCLUDE

Additionally to

  <TMPL_INCLUDE NAME="file.htc">

you can do an include of a template variable:

  <TMPL_INCLUDE VAR="file_include_var">
  $htc->param(file_include_var => "file.htc");

Here the C<VAR=> part is necessary to distinguish from a static include.
  
=head2 VARIABLE ACCESS

With HTC, you have more control over how you access your template
parameters. An example:

  my %hash = (
    SELF => '/path/to/script.pl',
    LANGUAGE => 'de',
    BAND => 'Bauhaus',
    ALBUMS => [
    {
      NAME => 'Mask',
      SONGS => [ { NAME => 'Hair of the Dog' }, ... ],
    },
    ],
    INFO => {
      BIOGRAPHY => '...',
      LINK => '...'
    },
  );

Now in the TMPL_LOOP C<ALBUMS> you would like to access the path to
your script, stored in $hash{SELF}. in HTML::Template you have to set
the option C<global_vars>, so you can access C<$hash{SELF}> from
everywhere. Unfortunately, now C<NAME> is also global, which isn't
a problem in this simple example, but in a more complicated template
this is impossible. With HTC, you wouldn't use C<global_vars> here, but
you can say:

  <TMPL_VAR .SELF>

to access the root element, and you could even say C<.INFO.BIOGRAPHY>
or C<ALBUMS.0.SONGS.0.NAME>

=head2 RENDERING OBJECTS

This is still experimental. You have been warned.

Additionally to feeding a simple hash do HTC, you can feed it objects.
To do method calls you can use '->' in the template or define a different string
if you don't like that.

  my $htc = HTML::Template::Compiled->new(
    ...
    method_call => '.', # default ->
    deref       => '/', # default .
  );

  $htc->param(
    VAR => "blah",
    OBJECT => bless({...}, "Your::Class"),
  );

  <TMPL_VAR NAME="OBJECT.fullname">
  <TMPL_WITH OBJECT>
  Name: <TMPL_VAR _.fullname>
  </TMPL_WITH>

C<fullname> will call the fullname method of your Your::Class object.
You have to use C<_> here because with using only C<fullname> HTC couldn't
know if you want to dereference a hash or do a method call.

The default values might change in the future depending on what people use most,
so at the moment it's the best to always set the options.

And please don't set deref and method call to the same value - this won't work.

=head2 DEBUGGING

For printing out the contents of all the parameters you can do:

  <TMPL_LOOP ALBUMS>
  Dump: <TMPL_VAR _ ESCAPE=DUMP|HTML>
  </TMPL_LOOP>

The special name C<_> gives you the current parameter and C<ESCAPE=DUMP>
will by default generate a Data::Dumper output of the
current variable, in this case it will dump out the contents of every
album in a loop. To correctly display that in html C<|HTML> will escape html
entities.

=head2 TMPL_WITH

If you have a deep leveled hash you might not want to write 
THE.FULL.PATH.TO.YOUR.VAR always. Jump to your desired level once and
then you need only one level. Compare:

  <TMPL_WITH DEEP.PATH.TO.HASH>
  <TMPL_VAR NAME>: <TMPL_VAR AGE>
  </TMPL_WITH>

  <TMPL_VAR DEEP.PATH.TO.HASH.NAME>: <TMPL_VAR DEEP.PATH.TO.HASH.AGE>

=head2 TMPL_LOOP

The special name C<_> gives you the current paramater. In loops you can use it like this:

 <tmpl_loop foo>
  Current item: <tmpl_var _ >
 </tmpl_loop>

=head2 TMPL_COMMENT

For debugging purposes you can temporarily comment out regions:

  <tmpl_var wanted>
    <tmpl_comment outer>
      <tmpl_comment inner>
        <tmpl_var unwanted>
      </tmpl_comment inner>
      <tmpl_var unwanted>
  </tmpl_comment outer>

  $htc->param(unwanted => "no thanks", wanted => "we want this");

The output is (whitespaces stripped):

  we want this
  <tmpl_var unwanted>
  <tmpl_var unwanted>

HTC will ignore anything between COMMENT directives.
This is useful for debugging, and also for documentation inside the
template which should not be outputted.

=head2 TMPL_NOPARSE

Anything between

  <tmpl_noparse>...</tmpl_noparse>

will not be recognized as template directives. Same syntax as TMPL_COMMENT.
It will output the content, though.

=head2 TMPL_SWITCH

The SWITCH directive has the same syntax as VAR, IF etc.
The CASE directive takes a simple string or a comma separated list of strings.
Yes, without quotes. I might add that if someone finds it useful.

 <tmpl_switch language>(or <tmpl_switch name=language>)
  <tmpl_case de>echt cool
  <tmpl_case en>very cool
  <tmpl_case es>superculo
  <tmpl_case fr,se>don't speak french or swedish
  <tmpl_case default>sorry, no translation for cool in language <%=lang%> available
  <tmpl_case>(same as default)
 </tmpl_switch>


=head2 OPTIONS

=over 4

=item path

Path to template files

=item search_path_on_include

Search the list of paths spcified with C<path> when including a tmplate.
Default is 1 (different from HTML::Template).

=item cache_dir

Path to caching directory (you have to create it before)

=item filename

Template to parse

=item scalarref

Reference to a scalar with your template content. It's possible to cache
scalarrefs, too, if you have Digest::MD5 installed. Note that your cache directory
might get filled with files from earlier versions. Clean the cache regularly.

Don't cache scalarrefs if you have dynamic strings. Your memory might get filled up fast!
Use the (still undocumented) option

  cache => 0

to disable memory caching.

=item arrayref

Reference to array containing lines of the template content (newlines have
to be included)

=item filehandle

Filehandle which contains the template content. Note that HTC will not cache
templates created like this.

=item loop_context_vars

Vars like C<__first__>, C<__last__>, C<__inner__>, C<__odd__>, C<__counter__>

=item global_vars

If set to 1, every outer variable can be accessed from anywhere in the enclosing scope.

=item deref

Define the string you want to use for dereferencing, default is C<.> at the
moment:

 <TMPL_VAR hash.key>

=item method_call

Define the string you want to use for method calls, default is -> at
the moment:

 <TMPL_VAR object->method>
 
=item line_numbers

For debugging: prints the line number of the wrong tag, e.g. if you have
a /TMPL_IF that does not have an opening tag.

=item case_sensitive

default is 1, set it to 0 to use this feature like in HTML::Template. Note that
this can slow down your program a lot.

=item dumper

  my $t = HTML::Template::Compiled->new(
    ...
    dumper = sub { my_cool_dumper($_[0]) },
  );
  ---
  <TMPL_VAR var ESCAPE=DUMP>
 

This will call C<my_cool_dumper()> on C<var>.

Alternatively you can use the DHTML plugin which is using C<Data::TreeDumper> and
C<Data::TreeDumper::Renderer::DHTML>. You'll get a  dumper like output which you can
collapse and expand, for example. See L<Data::TreeDumper> and L<Data::TreeDumper::Renderer::DHTML> for
more information.
Example:

  my $t = HTML::Template::Compiled->new(
    ...
    dumper = 'DHTML',
  );
 
For an example see C<examples/dhtml.html>.

=item out_fh

  my $t = HTML::Template::Compiled->new(
    ...
    out_fh => 1,
  );
  ...
  $t->output($fh); # or output(\*STDOUT) or even output()

This option is fixed, so if you create a template with C<out_fh>, every
output of this template will print to a specified (or default C<STDOUT>) filehandle.

=item filter

Filter template code before parsing.

  my $t = HTML::Template::Compiled->new(
    ...
    filter => sub { myfilter( ${$_[0]} ) },
    # or
    filter => [ {
        sub => sub { myfilter( ${$_[0]} ) },
        format => 'scalar', # or array
      },
      ...
    ],
  );

=item formatter

With formatter you can spcify how an object should be rendered. This is useful
if you don't want object methods to be called, but only a given subset of
methods.

  my $htc = HTML::Template::Compiled->new(
  ...
  formatter => {
    'Your::Class' => {
      fullname => sub {
        $_[0]->first . ' ' . $_[0]->last
      },
      first => Your::Class->can('first'),
      last => Your::Class->can('last'),
      },
    },
    formatter_path => '/', # default '/'
  );
  # $obj is a Your::Class object
  $htc->param(obj => $obj);
  # Template:
  # Fullname: <tmpl_var obj/fullname>

=item formatter_path

see formatter. Defaults to '/'

=item debug

If set to 1 you will get the generated perl code on standard error

=back

=head2 METHODS

=over 4

=item clear_cache ([DIR])

Class method. It will clear the memory cache either of a specified cache directory:

  HTML::Template::Compiled->clear_cache($cache_dir);

or all memory caches:

  HTML::Template::Compiled->clear_cache();

=item clear_filecache

Class- or object-method. Removes all generated perl files from a given directory.

  # clear a directory
  HTML::Template::Compiled->clear_filecache('cache_directory');
  # clear this template's cache directory (and not one template file only!)
  $htc->clear_filecache();

=item preload

Class method. Will preload all template files from a given cachedir into memory. Should
be done, for example in a mod_perl environment, at server startup, so all templates
go into shared memory

  HTML::Template::Compiled->preload($cache_dir);

If you don't do preloading in mod_perl, memory usage might go up if you have a lot
of templates.

=item clear_params

Empty all parameters.

=back

=head1 EXPORT

None.

=head1 CACHING

You create a template almost like in HTML::Template:

  my $t = HTML::Template::Compiled->new(
    path => 'templates',
    loop_context_vars => 1,
    filename => 'test.html',
    # for testing without cache comment out
    cache_dir => "cache",
  );

The next time you start your application and create a new template, HTC will read all generated
perl files, and a call to the constructor like above won't parse
the template, but just use the loaded code. If your template
file has changed, though, then it will be parsed again.

You can set $HTML::Template::Compiled::NEW_CHECK to the amount of
seconds you want to wait until the template is expired. So
C<$HTML::Template::Compiled::NEW_CHECK = 60 * 10;> will check after
10 minutes if the tmpl file was modified. Set it to a very high
value will then ignore any changes, until you delete the generated
code.

=head1 TODO

fix C<path> option, query, implement expressions, ...

=head1 BUGS

At the moment files with no newline at the end of the last line aren't correctly parsed.

Probably many more bugs I don't know yet =)

=head1 Why another Template System?

You might ask why I implement yet another templating system. There
are so many to choose from. Well, there are several reasons.

I like the syntax of HTML::Template *because* it is very restricted.
It's also easy to use (template syntax and API).
However, there are some things I miss I try to implement here.

I think while HTML::Template is quite good, the implementation can
be made more efficient (and still pure Perl). That's what I'm trying to achieve.

I use it in my web applications, so I first write it for
myself =)
If I can efficiently use it, it was worth it.

=head1 RESOURCES

See http://htcompiled.sf.net/ for current releases not yet on CPAN and for cvs access.

=head1 SEE ALSO

L<HTML::Template>

L<HTML::Template::JIT>

L<Template> - Toolkit

http://www.tinita.de/projects/perl/

=head1 AUTHOR

Tina Mueller

=head1 CREDITS

Sam Tregar big thanks for ideas and letting me use his L<HTML::Template> test suite

Bjoern Kriews for original idea and contributions

Ronnie Neumann, Martin Fabiani, Kai Sengpiel, Sascha Kiefer from perl-community.de for ideas and beta-testing

perlmonks.org and perl-community.de for everyday learning

Corion, Limbic~Region, tye, runrig and others from perlmonks.org 

=head1 COPYRIGHT AND LICENSE

Copyright (C) 2005 by Tina Mueller

This library is free software; you can redistribute it and/or modify
it under the same terms as Perl itself, either Perl version 5.8.3 or,
at your option, any later version of Perl 5 you may have available.


=cut
