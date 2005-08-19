package HTML::Template::Compiled;
# $Id: Compiled.pm,v 1.15 2005/08/19 17:51:56 tina Exp $
my $version = <<'=cut';
=pod

=head1 NAME

HTML::Template::Compiled - Template System Compiles HTML::Template files to Perl code

=head1 VERSION

our $VERSION = "0.34";

=cut
use Data::Dumper; $Data::Dumper::Indent = 1; $Data::Dumper::Sortkeys = 1;
use strict;
use warnings;
# doesn't work with make tardist
#our $VERSION = ($version =~ m/^our \$VERSION = "(\d+(?:\.\d+)+)"/m) ? $1 : "0.09";
our $VERSION = "0.34";

use Fcntl qw(:seek :flock);
eval {
	require HTML::Entities;
	require URI::Escape;
};

use vars qw($__first__ $__last__ $__inner__ $__odd__ $__counter__);
use vars qw($NEW_CHECK $UNDEF $ENABLE_ASP);
$NEW_CHECK = 60 * 10; # 10 minutes default
$UNDEF = ''; # set for debugging
$ENABLE_ASP = 1;

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

my $start_re = $ENABLE_ASP ? '(?i:<TMPL_|<!-- *TMPL_|<%)' : '(?i:<TMPL_|<!-- *TMPL_)';
my $end_re = $ENABLE_ASP ? '(?:>| *-->|%>)' : '(?:>| *-->)';
my $tmpl_re = $ENABLE_ASP ?
	'(?i:</?TMPL.*?>|<!-- */?TMPL_.*? *-->|<%/?.*?%>)' :
	'(?i:</?TMPL.*?>|<!-- */?TMPL_.*? *-->)';
my $close_re = $ENABLE_ASP ? '(?i:</TMPL_|<!-- */TMPL_|<%/)' : '(?i:</TMPL_|<!-- */TMPL_)';
my $var_re = '(?:[\w./]+|->)+';

# options / object attributes
use constant FILENAME => 0;
use constant DEBUG => 1;
use constant TEXT => 2;
use constant CODE => 3;
use constant PARAM => 4;
use constant PERL => 5;
use constant CACHE_DIR => 6;
use constant PATH => 7;
use constant LOOP_CONTEXT => 8;
use constant LINE_NUMBERS => 9;
use constant CASE_INSENSITIVE => 10;
use constant USE_OBJECTS => 11;
use constant METHOD_CALL => 12;
use constant DEREF => 13;

sub _line_numbers { shift->attr(LINE_NUMBERS, @_) }
sub filename { shift->attr(FILENAME, @_) }
sub debug { shift->attr(DEBUG, @_) }
sub text { shift->attr(TEXT, @_) }
sub code { shift->attr(CODE, @_) }
sub perl { shift->attr(PERL, @_) }
sub cache_dir { shift->attr(CACHE_DIR, @_) }
sub path { shift->attr(PATH, @_) }
sub _loop_context { shift->attr(LOOP_CONTEXT, @_) }
sub _case_insensitive { shift->attr(CASE_INSENSITIVE, @_) }
sub _use_objects {shift->attr(USE_OBJECTS, @_) }
sub _method_call {shift->attr(METHOD_CALL, @_) }
sub _deref {shift->attr(DEREF, @_) }

sub new {
	my $class = shift;
	my %args = @_;
	my $self = [];
	bless $self, $class;
	$args{path} ||= $ENV{'HTML_TEMPLATE_ROOT'} || '';
	length $args{path} and $args{path} .= '/' unless $args{path} =~ m#/$#;
	#print "PATH: $args{path}!!\n";
	$self->path($args{path});
	if (my $file = $args{filename}) {
		$self->filename($self->path().$file);
	}
	$self->init(%args);
	$self->debug($args{debug});
	$self->cache_dir($args{cache_dir}||"");
	$self->_read_cache;
	my $cached_or_new = $self->cached_or_new($self->filename, $self->cache_dir);
}

sub init {
	my ($self, %args) = @_;
	my %values = (
		# defaults
		use_objects => 1,
		method_call => '->',
		deref => '.',
		line_numbers => 0,
		loop_context_vars => 0,
		case_insensitive => 0,
		%args,
	);
	$self->_use_objects(1) if $values{use_objects};
	$self->_method_call($values{method_call});
	$self->_deref($values{deref});
	$self->_line_numbers(1) if $args{line_numbers};
	$self->_loop_context(1) if $args{loop_context_vars};
	$self->_case_insensitive(1) if $args{case_insensitive};
}

sub cached_or_new {
	my $self = shift;
	my ($file,$dir) = @_;
	my $cached = $self->cached($file,$dir);
	# see if we have a cache and if checktime is within
	# $NEW_CHECK
	if (defined $cached and (time - $cached->{checked} < $NEW_CHECK)) {
		# use the cache
		#print STDERR "use cache\n";
		#print STDERR "last check: $cached->{checked}\n";
		$self->perl($cached->{'sub'});
		return $self;
	}
	else {
		#print STDERR "new check\n";
		my $test = time;
		# no cache or $NEW_CHECK
		#my @times = $self->_checktimes($self->filename);
		my @times = $self->_checktimes($file);

		#print STDERR "($file)time: $test, mtime: $times[MTIME], cached mtime: $cached->{mtime}\n";
		#print STDERR "times:(@times)\n";
		# see if we have a cache and modified time of
		# file is more recent than our cache
		if($cached->{mtime} && $times[MTIME] <= $cached->{mtime}) {
			#print STDERR "template is old, use cache\n";
			$self->perl($cached->{'sub'});
			$cached->{'checked'} = time;
			return $self;
		}
		# else just move on and generate new template
	}
	#print STDERR "template is new, no cache\n";
	my @times = $self->_checktimes($self->filename);
	my $text = $self->_readfile($file);
	$self->text($text);
	my ($code,$sub) = $self->_compile($text,$file);
	$self->code($code);
	$self->perl($sub);
	$self->cache({
			'sub'=>$sub,
			checked=>time,
			mtime => $times[MTIME],
		},
		$code,$file);
	return $self;
}

sub _read_cache {
	my $self = shift;
	my $cache = $self->cache_dir or return;
	my $main = "$cache/HTC-Main.pm";
	return unless -f $main;
	require $main;
	$HTML::Template::Compiled::main::root = $cache;
	HTML::Template::Compiled::main::include($self);
}

sub attr {
	if (@_>2) {
		return $_[0]->[$_[1]] = pop;
	}
	return $_[0]->[$_[1]];
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
	if ($self->_line_numbers) {
		# split lines and preserve empty trailing lines
		my @lines = split /\n/, $text, -1;
		for my $i (0..$#lines) {
			$lines[$i] =~ s#($tmpl_re)#__${i}__$1#g;
		}
		$text = join "\n", @lines;
	}
	my @p = split m#((?:__\d+__)?$tmpl_re)#, $text;
	my $level = 1;
	my $code = '';
	my $stack = [];
	$code .= <<"EOM";
sub {
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
		if (s#__(\d+)__($tmpl_re)#$2#) {
			$line = $1;
		}
		my $meth = $self->_method_call;
		my $deref = $self->_deref;
		# --------- TMPL_VAR
		if (m#$start_re(VAR|=) +(?:NAME=)?(['"]?)($var_re)\2(?: +ESCAPE=(['"]?)(HTML|URI)\4)? *$end_re#i) {
			my $type = $1;
			$type = "VAR" if $type eq '=';
			my $var = $3;
			my $escape = $5 || "";
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
			if ($var eq '_') {
				# we want a dump
				$code .= qq#require Data::Dumper;\n#;
				$varstr = qq#Data::Dumper->Dump([\$\$sp],['DUMP'])#;
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
			if (uc $type eq 'VAR') {
				if (uc $escape eq 'HTML') {
					$code .= qq#${indent}\$OUT .= \$t->escape_html($varstr);\n#;
				}
				elsif (uc $escape eq 'URI') {
					$code .= qq#${indent}\$OUT .= \$t->escape_uri($varstr);\n#;
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
		elsif (m#${start_re}WITH (?:NAME=)?(['"]?)($var_re)\1$end_re#i) {
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
		elsif (m#${start_re}LOOP (?:NAME=)?(['"]?)($var_re)\1$end_re#i) {
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
			if ($self->_loop_context) {
			$code .= <<EOM;
${indent}    local \$__counter__ = \$ix;
${indent}    local \$__first__   = \$ix == \$[;
${indent}    local \$__last__    = \$ix == \$size;
${indent}    local \$__odd__     = \$ix % 2;
${indent}    local \$__inner__   = \$ix != \$[ && \$ix != \$size;
EOM
			}
		}

		# --------- TMPL_ELSE
		elsif (m#${start_re}ELSE *$end_re#i) {
			# we can only have an open if or unless
			$self->_checkstack($fname,$line,$stack, TELSE);
			my $indent = "  " x ($level-1);
			$code .= qq#${indent}}\n${indent}else {\n#;
		}

		# --------- / TMPL_IF TMPL UNLESS TMPL_WITH
		elsif (m#$close_re(IF|UNLESS|WITH)(?: $var_re)?$end_re#i) {
			$self->_checkstack($fname,$line,$stack, "$1");
			pop @$stack;
			$level--;
			my $indent = "  " x $level;
			$code .= qq#${indent}} \# end $1\n#;
		}

		# --------- / TMPL_LOOP
		elsif (m#${close_re}LOOP(?: $var_re)? *$end_re#i) {
			$self->_checkstack($fname,$line,$stack, TLOOP);
			pop @$stack;
			$level--;
			my $indent = "  " x $level;
			$code .= <<EOM;
${indent}  }
${indent}} # end loop
EOM
		}
		# --------- TMPL_IF TMPL UNLESS TMPL_ELSE
		elsif (m#$start_re(ELSIF|IF|UNLESS) (?:NAME=)?(['"]?)($var_re)\2$end_re#i) {
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
		elsif (m#${start_re}INCLUDE (?:NAME=)?(['"]?)([^'">]+)\1$end_re#i) {
			my $filename = $2;
			$filename = $self->path().$filename;
			# generate included template
			{
				#print "FILE: $filename!!\n";
				my $cached_or_new = $self->cached_or_new($filename, $self->cache_dir);
			}
			my $cache = $self->cache_dir;
			$code .= <<EOM;
${indent}\{
${indent}  my \$sub = \$t->cached_or_new("$filename", "$cache")->perl;
${indent}  \$OUT .= \$sub->(\$t, \$\$sp);
${indent}}
EOM

		}
		else {
			$_ = qq#q~$_~#;
			s#^q~~.##;
			s#.q~~##;
			$code .= qq#$indent\$OUT .= $_;\n#;
		}
		
	}
	$code .= "\n} # end of sub\n";
	print $code if $self->debug;
	my $sub = eval $code;
	die "code: $@" if $@;
	return $code, $sub;
	
}
use constant PATH_METHOD => 1;
use constant PATH_DEREF => 2;
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
			push @paths, '['.PATH_DEREF.",'".($self->_case_insensitive?uc $p:$p)."']";
		}
		else {
			push @paths, '['.PATH_DEREF.", '".($self->_case_insensitive?uc $p:$p)."']";
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

sub cache {
	my $self = shift;
	my ($sub, $code, $filename) = @_;
	#my $sub = $self->perl;
	my $cache = $self->cache_dir;
	$self->add_sub($filename, $cache, $sub);
	if (defined $cache && -d $cache) {
		$self->lock;
		my $main = "$cache/HTC-Main.pm"; # TODO File::Spec
		unless (-f $main) {
			my $code = $self->_maincode;
			open my $fh, ">$main" or die $!;
			print $fh $code;
			close $fh;
			require $main;
			die "code: $@" if $@;
			$HTML::Template::Compiled::main::root = $cache;
			#print "HTC-Main.pm generated\n";
		}
		my $plfile;
		my $trfile = $filename;
		$trfile =~ s#^./##; # TODO File::Spec
		$trfile =~ tr#/#:#; # TODO File::Spec
		$plfile = $trfile;
		{
			open my $fh, "+<", $main or die $!;
			while (<$fh>) {
				last if m/^__DATA__$/;
			}
			my $pos = tell $fh;
			my $found;
			my @files;
			while (<$fh>) {
				chomp;
				$found = 1 if $_ eq $plfile;
				push @files, "$_\n";
			}
			seek $fh, $pos, SEEK_SET;
			truncate $fh, $pos;
			print $fh @files;
			print $fh "$plfile\n" unless $found;
			close $fh;
		}
		my @times = $self->_checktimes($filename);
		open my $fh, ">$cache/$plfile.pl" or die $!; # TODO File::Spec
		print $fh <<EOM;
		package HTML::Template::Compiled;
# file date $times[LMTIME()]
\$HTML::Template::Compiled::main::hash{"$cache"}->{"$filename"}->{mtime} = $times[MTIME()];
# last checked date $times[LCHECKED()]
\$HTML::Template::Compiled::main::hash{"$cache"}->{"$filename"}->{checked} = $times[CHECKED()];
\$HTML::Template::Compiled::main::hash{"$cache"}->{"$filename"}->{sub} = 
$code
;
 1;
EOM
		#print "$cache/$plfile.pl generated\n";
		$self->unlock;
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

sub _maincode {
	my ($self) = @_;
	my $code;
	return $code . 'package HTML::Template::Compiled::main;'.<<'EOM'."__DATA__\n";

use strict;
use warnings;

use vars '$root';
sub include {
	my $t = shift;
	while (<DATA>) {
		chomp;
		#warn "require ($root/$_.pl)";
		require "$root/$_.pl";
	}
	my $dir = $t->cache_dir;
	while (my ($key, $v) = each %{$HTML::Template::Compiled::main::hash{$dir}}) {
		$t->add_sub($key, $dir, $v);
	}
}
1;
EOM
}
sub lock {
	my $file = $_[0]->cache_dir . "/lock"; # TODO File::Spec
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

{
	my %cache;
	sub add_sub {
		my ($self,$file, $dir, $code) = @_;
		#print "add_sub($self,$file, $dir, $code)\n";
		$dir = "" unless defined $dir;
		$dir ||= "";
		$cache{$dir}->{$file} = $code;
	}
	sub cached {
		#print Dumper \%cache;
		my ($self,$file, $dir) = @_;
		$dir = "" unless defined $dir;
		return $cache{$dir}->{$file};
	}
	sub clear_cache {
		my $dir = $_[0]->cache_dir;
		$cache{$dir} = {};
	}
}
sub param {
	my $self = shift;
	unless (@_) {
		return $self->[PARAM];
	}
	my %p = @_;
	if ($self->_case_insensitive) {
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
	my $f = $self->filename;
	#print STDERR "+++++++++++++++++++++++++++++ FILENAME $f\n";
	$self->perl()->($self,$p);
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
and once that is done, generating the output is much quicker (20 times)
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

=item ESCAPE=(HTML|URI)

=item C<__first__>, C<__last__>, C<__inner__>, C<__odd__>, C<__counter__>

=item <!-- TMPL_VAR NAME=PARAM1 -->

=item case insensitive var names

use option case_insensitive => 1 to use this feature

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
can use <% %> tags and the <%= tag instead of <%VAR (which will work, too):

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
  Dump: <TMPL_VAR _>
  </TMPL_LOOP>

The special name C<_> will give you a Data::Dumper output of the
current variable, in this case it will dump out the contents of every
album in a loop.

=head2 TMPL_WITH

If you have a deep leveled hash you might not want to write 
THE.FULL.PATH.TO.YOUR.VAR always. Jump to your desired level once and
then you need only one level. Compare:

  <TMPL_WITH DEEP.PATH.TO.HASH>
  <TMPL_VAR NAME>: <TMPL_VAR AGE>
  </TMPL_WITH>

  <TMPL_VAR DEEP.PATH.TO.HASH.NAME>: <TMPL_VAR DEEP.PATH.TO.HASH.AGE>


=head2 Options

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

=item case_insensitive

default is 0, set it to 1 to use this feature like in HTML::Template. Note that
this can slow down your program

=back

=head1 EXPORT

None.

=head1 CACHING

You create a template almost like in HTML::Template:

  my $t1 = HTML::Template::Compiled->new(
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
scalarref, filehandle, debugging option, filters, query, using
File::Spec for portability, fixing HTC-Main.pm, maybe implement
expressions, ...

=head1 BUGS

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

Bjoern Kriews (Original Idea)

Ronnie Neumann, Martin Fabiani for ideas and beta-testing

=head1 COPYRIGHT AND LICENSE

Copyright (C) 2005 by Tina Mueller

This library is free software; you can redistribute it and/or modify
it under the same terms as Perl itself, either Perl version 5.8.3 or,
at your option, any later version of Perl 5 you may have available.


=cut
