package HTML::Template::Compiled;
# $Id: Compiled.pm,v 1.36 2005/09/01 23:50:08 tina Exp $
my $version_pod = <<'=cut';
=pod

=head1 NAME

HTML::Template::Compiled - Template System Compiles HTML::Template files to Perl code

=head1 VERSION

our $VERSION = "0.42";

=cut
# doesn't work with make tardist
#our $VERSION = ($version_pod =~ m/^our \$VERSION = "(\d+(?:\.\d+)+)"/m) ? $1 : "0.01";
our $VERSION = "0.42";
use Data::Dumper; $Data::Dumper::Indent = 1; $Data::Dumper::Sortkeys = 1;
use strict;
use warnings;

use Fcntl qw(:seek :flock);
use File::Spec;
use HTML::Template::Compiled::Utils qw(:walkpath);
# TODO
eval {
	require HTML::Entities;
	require URI::Escape;
};

use vars qw($__first__ $__last__ $__inner__ $__odd__ $__counter__);
use vars qw($NEW_CHECK $UNDEF $ENABLE_ASP);
$NEW_CHECK = 60 * 10; # 10 minutes default
$UNDEF = ''; # set for debugging
$ENABLE_ASP = 1;

use constant D => 0;
use constant MTIME => 0;
use constant CHECKED => 1;
use constant LMTIME => 2;
use constant LCHECKED => 3;
use constant TIF => 'IF';
use constant TUNLESS => 'UNLESS';
use constant TELSIF => 'ELSIF';
use constant TELSE => 'ELSE';
use constant TLOOP => 'LOOP';
use constant TWITH => 'WITH';

# TODO
my $start_re = $ENABLE_ASP ? '(?i:<TMPL_|<!--\s*TMPL_|<%)' : '(?i:<TMPL_|<!--\s*TMPL_)';
my $end_re = $ENABLE_ASP ? '(?:>|\s*-->|%>)' : '(?:>|\s*-->)';
my $tmpl_re = $ENABLE_ASP ?
	'(?i:</?TMPL.*?>|<!--\s*/?TMPL_.*?\s*-->|<%/?.*?%>)' :
	'(?i:</?TMPL.*?>|<!--\s*/?TMPL_.*?\s*-->)';
my $close_re = $ENABLE_ASP ? '(?i:</TMPL_|<!--\s*/TMPL_|<%/)' : '(?i:</TMPL_|<!--\s*/TMPL_)';
my $var_re = '(?:[\w./]+|->)+';

# options / object attributes
use constant PARAM => 14;

{
	my @map = qw(
		filename debug file source perl cache_dir path loop_context
	 	line_numbers case_sensitive dumper method_call deref cache);
	for my $i (0..$#map) {
		my $method = ucfirst $map[$i];
		my $get = sub { return $_[0]->[$i] };
		my $set = sub { $_[0]->[$i] = $_[1] };
		no strict 'refs';
		*{"get$method"} = $get;
		*{"set$method"} = $set;
	}
}

sub new {
	my ($class, %args) = @_;
	my $self = [];
	bless $self, $class;
	$args{path} ||= $ENV{'HTML_TEMPLATE_ROOT'} || '';
	#print "PATH: $args{path}!!\n";
	if ($args{perl}) {
		# we have perl code already!
		$self->init(%args);
		$self->setPerl($args{perl});
		$self->setCache(exists $args{cache}?$args{cache}:1);
		$self->setFilename($args{filename});
		$self->setCache_dir($args{cache_dir});
		$self->setPath($args{path});
		my $file = $self->createFilename($self->getPath,$self->getFilename);
		$self->setFile($file);
		return $self;
	}
	if (my $filename = $args{filename}) {
		my $t = $self->create(%args);
		return $t;
	}
}

sub create {
	my ($self, %args) = @_;
	D && $self->stack;
	if (%args) {
		$self->setCache(exists $args{cache}?$args{cache}:1);
		$self->setFilename($args{filename});
		$self->setCache_dir($args{cache_dir});
		$self->setPath($args{path});
	}
	else {
		#my $file = $self->createFilename($self->getPath,$self->getFilename);
		#$self->setFile($file);
	}
	my $t = $self->fromCache();
	return $t if $t;
	# ok, seems we have nothing in cache, so compile
	my $file = $self->createFilename($self->getPath,$self->getFilename);
	$self->setFile($file);
	$self->init(%args) if %args;
	$self->compile();
	return $self;
}
sub fromCache {
	my ($self) = @_;
	my $t;
	# try to get memory cache
	if ($self->getCache) {
		$t = $self->fromMemCache();
		return $t if $t;
	}
	# not in memory cache, try file cache
	if ($self->getCache_dir) {
		$t = $self->include();
		return $t if $t;
	}
	return;
}

{
	my $cache;
	my $times;
	sub fromMemCache {
		my ($self, %args) = @_;
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
	sub addCache {
		my ($self, %times) = @_;
		my $dir = $self->getCache_dir;
		$dir = '' unless defined $dir;
		my $fname = $self->getFilename;
		D && $self->log("addCache ".$fname);
		$cache->{$dir}->{$fname} = $self;
		$times->{$dir}->{$fname} = \%times;
	}
}
sub compile {
	my ($self) = @_;
	#my $file = $self->createFilename($self->getPath,$self->getFilename);
	my $file = $self->getFile;
	#$self->setFile($file);
	#$self->log("compile $file");
	my @times = $self->_checktimes($self->getFile);
	my $text = $self->_readfile($file);
	my ($source,$compiled) = $self->_compile($text,$file);
	$self->setPerl($compiled);
	$self->addCache(
		checked=>time,
		mtime => $times[MTIME],
	);
	D && $self->log("compiled $file");
	if ($self->getCache_dir) {
		D && $self->log("addFileCache($file)");
		$self->addFileCache($source,
			checked=>time,
			mtime => $times[MTIME],
		);
	}
}
sub addFileCache {
	my ($self, $source, %times) = @_;
	$self->lock;
	my $cache = $self->getCache_dir;
	my $plfile = $self->escape_filename($self->getFile);
	my $filename = $self->getFilename;
	my $lmtime = localtime $times{mtime};
	my $lchecked = localtime $times{checked};
	open my $fh, ">$cache/$plfile.pl" or die $!; # TODO File::Spec
	print $fh <<EOM;
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
		filename => '@{[$self->getFilename]}',
		file => '@{[$self->getFile]}',
		path => '@{[$self->getPath]}',
		method_call => '@{[$self->getMethod_call]}',
		deref => '@{[$self->getDeref]}',
		# template subroutine
		perl => $source,
		# template subroutine
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
	D && $self->log("require $req");
	my $r = do "$req";
	my $args = $r->{htc};
	my $t = HTML::Template::Compiled->new(%$args);
	D && $self->log("include",$t,"$args->{perl}");
	return unless $self->uptodate($r->{times});
	$t->addCache(
		checked=>$r->{times}->{checked},
		mtime => $r->{times}->{mtime},
	);
	return $t;
}

sub createFilename {
	my ($self,$path,$filename) = @_;
	D && $self->log("createFilename($path,$filename)");
	if (!length $path or File::Spec->file_name_is_absolute($filename)) {
		return $filename;
	}
	else {
		return File::Spec->catfile($path, $filename);
	}
}

sub uptodate {
	my ($self, $times) = @_;
	my $now = time;
	if ($now - $times->{checked} < $NEW_CHECK) {
		return 1;
	}
	else {
		my $file = $self->createFilename($self->getPath,$self->getFilename);
		$self->setFile($file);
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
		return Data::Dumper->Dump([$var],['DUMP']);
	}
}

sub init {
	my ($self, %args) = @_;
	my %values = (
		# defaults
		method_call => '->',
		deref => '.',
		line_numbers => 0,
		loop_context_vars => 0,
		case_sensitive => 1,
		%args,
	);
	$self->setMethod_call($values{method_call});
	$self->setDeref($values{deref});
	$self->setLine_numbers(1) if $args{line_numbers};
	$self->setLoop_context(1) if $args{loop_context_vars};
	$self->setCase_sensitive($values{case_sensitive});
	$self->setDumper($args{dumper}) if $args{dumper};
	$self->setDebug($args{debug});
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
	my $stack = [];
	$code .= <<"EOM";
sub {
	#local *__ANON__ = "htc_$fname";
	my (\$t, \$p) = \@_;
	my \$OUT;
	my \$sp = \\\$p;
EOM
	for (@p) {
		my $indent = "  " x $level;
		#s/\n/\\n/g;
		s/~/\\~/g;
		
		#$code .= qq#\# line 1000\n#;
		#$self->{code} .= qq#$indent print "sp: \$\$sp\\n";#;

		my $line = 0;
		if ($self->getLine_numbers && s#__(\d+)__($tmpl_re)#$2#) {
			$line = $1;
		}
		my $meth = $self->getMethod_call;
		my $deref = $self->getDeref;
		# --------- TMPL_VAR
		if (m#$start_re(VAR|=)\s+(?:NAME=)?(['"]?)($var_re)\2.*$end_re#i) {
			my $type = $1;
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
				deref => $deref,
				method_call => $meth,
				var => $var,
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
				$code .= qq#${indent}\{\n${indent}  my \$sp = \$sp;\n#;
			}
			if ($root) {
				$code .= qq#${indent}  \$sp = \\\$p;\n#;
			}
			if ($path) {
				my @paths = split /\./, $var;
				my $s = join ",", map { "'\Q$_\E'" } @paths;
				my $varstr = $self->_make_path(
					deref => $deref,
					method_call => $meth,
					var => $var,
				);
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
					$code .= qq#${indent}\$OUT .= $varstr;\n#;
				}
				else {
					#$code .= qq#print STDERR "<<<<<<<<<<< $var\\n";\n\# line 1000\n#;
					$code .= qq#${indent}\$OUT .= $varstr;\n#;
				}
			}
			if ($root || $path) {
				$code .= qq#\n${indent}}\n#;
			}
		}

		# --------- TMPL_WITH
		elsif (m#${start_re}WITH\s+(?:NAME=)?(['"]?)($var_re)\1\s*$end_re#i) {
			push @$stack, TWITH;
			$level++;
			my $var = $2;
			my $varstr = $self->_make_path(
				deref => $deref,
				method_call => $meth,
				var => $var,
			);
			$code .= qq#${indent}\{ \# WITH $var\n#;
			$code .= qq#${indent}  my \$sp = \\$varstr;\n#;
		}

		# --------- TMPL_LOOP
		elsif (m#${start_re}LOOP\s+(?:NAME=)?(['"]?)($var_re)\1\s*$end_re#i) {
			push @$stack, TLOOP;
			my $var = $2;
			my $varstr = $self->_make_path(
				deref => $deref,
				method_call => $meth,
				var => $var,
			);
			$level+=2;
			$code .= <<EOM;
${indent}\{
${indent}  my \$size = \$#{ $varstr };

${indent}  # loop over $var
${indent}  for my \$ix (\$[..\$size) {
${indent}    my \$sp = \\ (${varstr}->[\$ix]);
EOM
			if ($self->getLoop_context) {
			$code .= <<EOM;
${indent}    local \$__counter__ = \$ix+1;
${indent}    local \$__first__   = \$ix == \$[;
${indent}    local \$__last__    = \$ix == \$size;
${indent}    local \$__odd__     = \$ix % 2;
${indent}    local \$__inner__   = \$ix != \$[ && \$ix != \$size;
EOM
			}
		}

		# --------- TMPL_ELSE
		elsif (m#${start_re}ELSE\s*$end_re#i) {
			# we can only have an open if or unless
			$self->_checkstack($fname,$line,$stack, TELSE);
			my $indent = "  " x ($level-1);
			$code .= qq#${indent}}\n${indent}else {\n#;
		}

		# --------- / TMPL_IF TMPL UNLESS TMPL_WITH
		elsif (m#$close_re(IF|UNLESS|WITH)(?:\s+$var_re)?\s*$end_re#i) {
			$self->_checkstack($fname,$line,$stack, "$1");
			pop @$stack;
			$level--;
			my $indent = "  " x $level;
			$code .= qq#${indent}} \# end $1\n#;
		}

		# --------- / TMPL_LOOP
		elsif (m#${close_re}LOOP(?:\s*$var_re\s*)?\s*$end_re#i) {
			$self->_checkstack($fname,$line,$stack, TLOOP);
			pop @$stack;
			$level--;
			$level--;
			my $indent = "  " x $level;
			$code .= <<EOM;
${indent}  }
${indent}} # end loop
EOM
		}
		# --------- TMPL_IF TMPL UNLESS TMPL_ELSE
		elsif (m#$start_re(ELSIF|IF|UNLESS)\s+(?:NAME=)?(['"]?)($var_re)\2\s*$end_re#i) {
			my $type = $1;
			my $var = $3;
			my $varstr = $self->_make_path(
				deref => $deref,
				method_call => $meth,
				var => $var,
			);
			#my $if = (lc $1 eq 'IF'? 'if' : "unless ");
			my $if = {IF => 'if', UNLESS => 'unless', ELSIF => 'elsif'}->{uc $1};
			my $elsif = uc $1 eq 'ELSIF' ? 1 : 0;
			if ($elsif) {
				$code .= qq#${indent}\}\n#;
				$self->_checkstack($fname,$line,$stack, TELSIF);
			}
			else {
				push @$stack, $type;
				$level++;
			}
			$code .= <<EOM
${indent}$if($varstr) {
EOM
		}
		elsif (m#${start_re}INCLUDE\s+(?:NAME=)?(['"]?)([^'">]+)\1\s*$end_re#i) {
			my $filename = $2;
			#$filename = $self->getPath().'/'.$filename;
			my $path = $self->getPath();
			# generate included template
			{
				D && $self->log("compile include $filename!!");
				my $cached_or_new = $self->clone_init($path, $filename, $self->getCache_dir);
			}
			my $cache = $self->getCache_dir;
			$code .= <<EOM;
${indent}\{
${indent}  my \$new = \$t->clone_init('$path','$filename', '$cache');
${indent}  \$OUT .= \$new->getPerl()->(\$new,\$\$sp);
${indent}}
EOM

		}
		else {
			if (length $_) {
				s/\\/\\\\/g;
				s/'/\\'/g;
				#$_ = qq#q~$_~#;
				#s#^q~~.##;
				#s#.q~~##;
				#$code .= qq#$indent\$OUT .= $_;\n#;
				$code .= qq#$indent\$OUT .= '$_';\n#;
			}
		}
		
	}
	$code .= "\n} # end of sub\n";
	print STDERR $code if $self->getDebug;
	my $sub = eval $code;
	die "code: $@" if $@;
	return $code, $sub;
	
}
sub _make_path {
	my ($self, %args) = @_;
	my $root = 0;
	if ($args{var} =~ m/^__(\w+)__$/) {
		return "\$$args{var}";
	}
	if ($args{var} =~ s/^_//) {
		$root = 0;
	}
	elsif ($args{var} =~ m/^(?:\Q$args{deref}\E|\Q$args{method_call}\E)/) {
		$root = 1;
	}
	my @split = split m/(?=\Q$args{deref}\E|\Q$args{method_call}\E)/, $args{var};
	my @paths;
	for my $p (@split) {
		if ($p =~ s/^\Q$args{method_call}//) {
			push @paths, '['.PATH_METHOD.",'$p']";
		}
		elsif ($p =~ s/^\Q$args{deref}//) {
			push @paths, '['.PATH_DEREF.",'".($self->getCase_sensitive?$p:uc$p)."']";
		}
		else {
			push @paths, '['.PATH_DEREF.", '".($self->getCase_sensitive?$p:uc$p)."']";
		}
	}
	local $" = ",";
	my $varstr = "\$t->_walkpath(" .($root?'$p':'$$sp').",@paths)";
	return $varstr;
	return ($root, \@paths);
}

sub _walkpath {
	my ($self, $ref, @paths) = @_;
	my $walk = $ref;
	for my $path (@paths) {
		my ($type, $key) = @$path;
		#print STDERR "ref: $walk, key: $key\n";
		if ($type == PATH_DEREF) {
			if (ref $walk eq 'ARRAY') {
				$walk = $walk->[$key];
			}
			else {
				$walk = $walk->{$key};
			}
		}
		else {
			$walk = $walk->$key;
		}
	}
	#print STDERR "return $walk\n";
	return $walk;
}

{
	my %map = (
		IF => [TIF,TUNLESS],
		UNLESS => [TUNLESS],
		ELSIF => [TIF,TUNLESS],
		ELSE => [TIF,TUNLESS,TELSIF],
		LOOP => [TLOOP],
		WITH => [TWITH],
	);
	sub _checkstack {
		my ($self, $fname,$line, $stack, $check) = @_;
		#print "_checkstack(@$stack, $check)\n";
		my @allowed = @{ $map{$check} } or return 1;
		die "Closing tag 'TMPL_$check' does not have opening tag at $fname line $line\n" unless @$stack;
		for (@allowed) {
			return 1 if $_ eq $stack->[-1];
		}
		die "'TMPL_$check' does not match opening tag ($stack->[-1]) at $fname line $line\n";
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
	my	$self = shift;
	my $filename = shift;
	#print STDERR "_checktimes($filename)\n";
	my $mtime = (stat $filename)[9];
	#print STDERR "stat $filename = $mtime\n";
	my $checked = time;
	my $lmtime = localtime $mtime;
	my $lchecked = localtime $checked;
	return ($mtime, $checked, $lmtime, $lchecked);
}

sub clone {
	my ($self) = @_;
	my $new = bless [@$self], ref $self;
	$new;
}
sub clone_init {
	my ($self, $path,$filename,$file,$cache) = @_;
	my $new = bless [@$self], ref $self;
	$new->setFilename($filename);
	$new->setPath($path);
	#$new->setFile($new->createFilename($path,$filename));
	$new = $new->create;
	$new;
}
{
	my %cache;
	my %objects;
	sub clear_cache {
		my $dir = $_[0]->getCache_dir;
		$cache{$dir} = {};
	}
}
sub param {
	my $self = shift;
	unless (@_) {
		return $self->[PARAM];
	}
	if (@_ == 1) {
		# feed a hashref or object
		$self->[PARAM] = $_[0];
		return;
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
	my $self = shift;
	my $p = $self->param;
	my $f = $self->getFile;
	$self->getPerl()->($self,$p);
}

sub lock {
	my $file = $_[0]->getCache_dir . "/lock"; # TODO File::Spec
	unless (-f $file) {
		open LOCK, ">$file";
		close LOCK;
	}
	open LOCK, "+<$file";
	flock LOCK, LOCK_EX;
}
sub unlock {
	close LOCK;
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
	return unless D;
	my ($self) = @_;
	my $i = 0;
	my $out;
	while(my @c = caller($i)) {
		$out .= "$i\t$c[0] l .$c[2] $c[3]\n";
		$i++;
	}
	print STDERR $out;
}
sub log {
	return unless D;
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
and once that is done, generating the output is much quicker (5 times)
than with HTML::Template (at least with my tests). It also can generate
perl files so that the next time the template is loaded it doesn't have to
be parsed again. The best performance gain is probably reached in
applications running under mod_perl, for example.

HTC does not implement all features of HTML::Template (yet), and
it has got some additional features which are explained below.

HTC will complain if you have a closing tag that does not fit
the last opening tag. To get the line number, set the line_numbers-option
(See L<"OPTIONS"> below)

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

=back

=head2 ADDITIONAL FEATURES

=over 4

=item TMPL_ELSIF

=item TMPL_WITH

=item Generating perl code

=item more variable access

see L<"VARIABLE ACCESS">

=item rendering objcets

see L<"RENDERING OBJECTS">

=item asp/jsp-like templates

For those who like it (i like it because it is shorter than TMPL_), you
can use E<lt>% %E<gt> tags and the E<lt>%= tag instead of E<lt>%VAR (which will work, too):

 <%IF blah%>  <%= VARIABLE%>  <%/IF>

=back

=head2 MISSING FEATURES

There are some features of H::T that are missing and that I don't plan
to implement. I'll try to list them here.

=over 4

=item C<global_vars>

No, I don't want to look in the whole
hash for a var name. If you want to use a variable, you should
know where it is.

=item C<die_on_bad_params>

I don't think I'll implement that in the near future.

=back

=head2 ESCAPING

Like in HTML::Template, you have C<ESCAPE=HTML> and C<ESCAPE=URL>. (C<ESCAPE=1> will follow.)
Additionally you have C<ESCAPE=DUMP>, which by default will generate a Data::Dumper output.
You can change that output by setting a different dumper function, see L<"OPTIONS"> dumper.

You can also chain different escapings, like C<ESCAPE=DUMP|HTML>.

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
this is impossible. With HTC, you don't have C<global_vars>, but
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


=head2 OPTIONS

=over 4

=item path

Path to template files

=item cache_dir

Path to caching directory (you have to create it before)

=item filename

Template to parse

=item loop_context_vars

Vars like C<__first__>, C<__last__>, C<__inner__>, C<__odd__>, C<__counter__>

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
this can slow down your program.

=item dumper

  my $t = HTML::Template::Compiled->new(
    ...
    dumper = sub { my_cool_dumper($_[0]) },
  );
  ---
  <TMPL_VAR var ESCAPE=DUMP>
 

This will call C<my_cool_dumper()> on C<var>.

Alternatevily you can use the DHTML plugin which is using C<Data::TreeDumper> and
C<Data::TreeDumper::Renderer::DHTML>. You'll get a  dumper like output which you can
collapse and expand, for example. See L<Data::TreeDumper> and L<Data::TreeDumper::Renderer::DHTML> for
more information.
Example:

  my $t = HTML::Template::Compiled->new(
    ...
    dumper = 'DHTML',
  );
 
test.

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

The next time you start your application, HTC will read all generated
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

Better access to cached perl files,
scalarref, filehandle, filters, query, using
File::Spec for portability, maybe implement expressions, ...

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

=head1 SEE ALSO

L<HTML::Template>

http://www.tinita.de/projects/perl/

=head1 AUTHOR

Tina Mueller

=head1 CREDITS

Bjoern Kriews for original idea and contributions

Ronnie Neumann, Martin Fabiani for ideas and beta-testing

=head1 COPYRIGHT AND LICENSE

Copyright (C) 2005 by Tina Mueller

This library is free software; you can redistribute it and/or modify
it under the same terms as Perl itself, either Perl version 5.8.3 or,
at your option, any later version of Perl 5 you may have available.


=cut
