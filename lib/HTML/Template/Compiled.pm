package HTML::Template::Compiled;
# $Id: Compiled.pm,v 1.187 2006/06/20 22:47:11 tinita Exp $
my $version_pod = <<'=cut';
=pod

=head1 NAME

HTML::Template::Compiled - Template System Compiles HTML::Template files to Perl code

=head1 VERSION

$VERSION = "0.68"

=cut
# doesn't work with make tardist
#our $VERSION = ($version_pod =~ m/^\$VERSION = "(\d+(?:\.\d+)+)"/m) ? $1 : "0.01";
our $VERSION = "0.68";
use Data::Dumper;
local $Data::Dumper::Indent = 1; local $Data::Dumper::Sortkeys = 1;
use constant D => 0;
use strict;
use warnings;

use Carp;
use Fcntl qw(:seek :flock);
use File::Spec;
use File::Basename qw(dirname);
use HTML::Template::Compiled::Utils qw(:walkpath :log :escape);
use HTML::Template::Compiled::Expression::Expressions;
# TODO
eval {
    require Digest::MD5;
    require HTML::Entities;
    require URI::Escape;
};
use HTML::Template::Compiled::Parser qw(
    $CASE_SENSITIVE_DEFAULT
    $NEW_CHECK
    $ENABLE_SUB
    $DEBUG_DEFAULT
    $SEARCHPATH
    %FILESTACK %SUBSTACK $DEFAULT_ESCAPE $DEFAULT_QUERY
    $UNTAINT $DEFAULT_TAGSTYLE
  $UNDEF

);
use vars qw(
  $__first__ $__last__ $__inner__ $__odd__ $__counter__
);

use constant MTIME    => 0;
use constant CHECKED  => 1;
use constant LMTIME   => 2;
use constant LCHECKED => 3;

use constant T_VAR     => 'VAR';
use constant T_IF       => 'IF';
use constant T_UNLESS   => 'UNLESS';
use constant T_ELSIF    => 'ELSIF';
use constant T_ELSE     => 'ELSE';
use constant T_IF_DEFINED => 'IF_DEFINED';
use constant T_END      => '__EOT__';
use constant T_WITH     => 'WITH';
use constant T_SWITCH   => 'SWITCH';
use constant T_CASE     => 'CASE';
use constant T_INCLUDE  => 'INCLUDE';
use constant T_LOOP    => 'LOOP';
use constant T_WHILE   => 'WHILE';
use constant T_LOOP_CONTEXT => 'LOOP_CONTEXT';
use constant T_INCLUDE_VAR => 'INCLUDE_VAR';

use constant INDENT   => '    ';

use constant NO_TAG      => 0;
use constant OPENING_TAG => 1;
use constant CLOSING_TAG => 2;

# options / object attributes
use constant PARAM => 0;
use constant PATH => 1;
# TODO
# sub getPath {
#     return $_[0]->[PATH];
# }
# sub setPath {
#     if (ref $_[1] eq 'ARRAY') {
#         $_[0]->[PATH] = $_[1]
#     }
#     elsif (defined $_[1]) {
#         $_[0]->[PATH] = [ $_[1] ]
#     }
# }

BEGIN {
    my @map = (
        undef, qw(
          path filename file scalar filehandle
          cache_dir cache search_path_on_include
          loop_context case_sensitive dumper global_vars
          method_call deref formatter_path default_path
          debug perl out_fh default_escape
          filter formatter
          globalstack use_query parser
          )
    );

    for my $i ( 1 .. @map ) {
        my $method = ucfirst $map[$i];
        my $get    = eval qq#sub { return \$_[0]->[$i] }#;
        my $set;
            $set = eval qq#sub { \$_[0]->[$i] = \$_[1] }#;
        no strict 'refs';
        *{"get$method"} = $get;
        *{"set$method"} = $set;
    }
}

sub new {
    my ( $class, %args ) = @_;
    my $self = [];
    bless $self, $class;
    $args{path} ||= $ENV{'HTML_TEMPLATE_ROOT'} || '';

    #print "PATH: $args{path}!!\n";
    if ( $args{perl} ) {
        D && $self->log("new(perl) filename: $args{filename}");

        # we have perl code already from cache!
        $self->init(%args);
        $self->setPerl( $args{perl} );
        $self->setCache( exists $args{cache} ? $args{cache} : 1 );
        $self->setFilename( $args{filename} );
        $self->setCache_dir( $args{cache_dir} );
        $self->setPath( $args{path} );
        $self->setScalar( $args{scalarref} );

        unless ( $self->getScalar ) {
            my $file =
              $self->createFilename( $self->getPath, $self->getFilename );
            $self->setFile($file);
        }
        return $self;
    }

    # handle the "type", "source" parameter format (does anyone use it?)
    if ( exists( $args{type} ) ) {
        exists( $args{source} )
          or croak(
            "$class->new() called with 'type' parameter set, but no 'source'!");
        (
                 $args{type} eq 'filename'
              or $args{type} eq 'scalarref'
              or $args{type} eq 'arrayref'
              or $args{type} eq 'filehandle'
          )
          or croak(
"$class->new() : type parameter must be set to 'filename', 'arrayref', 'scalarref' or 'filehandle'!"
          );
        $args{ $args{type} } = $args{source};
        delete $args{type};
        delete $args{source};
    }

    # check for too much arguments
    my $source_count = 0;
    exists( $args{filename} )   and $source_count++;
    exists( $args{filehandle} ) and $source_count++;
    exists( $args{arrayref} )   and $source_count++;
    exists( $args{scalarref} )  and $source_count++;
    if ( $source_count != 1 ) {
        croak(
"$class->new called with multiple (or no) template sources specified!"
              . "A valid call to new() has exactly ne filename => 'file' OR exactly one"
              . " scalarref => \\\$scalar OR exactly one arrayref => \\\@array OR"
              . " exactly one filehandle => \*FH" );
    }

    # check that filenames aren't empty
    if ( exists( $args{filename} ) ) {
        croak("$class->new called with empty filename parameter!")
          unless defined $args{filename}
          and length $args{filename};
    }
    if (   defined $args{filename}
        or $args{scalarref}
        or $args{arrayref}
        or $args{filehandle} )
    {
        D && $self->log("new()");
        my $t = $self->create(%args);
        return $t;
    }
}

sub new_file {
    return shift->new( filename => @_ );
}

sub new_filehandle {
    return shift->new( filehandle => @_ );
}

sub new_array_ref {
    return shift->new( arrayref => @_ );
}

sub new_scalar_ref {
    return shift->new( scalarref => @_ );
}

sub create {
    my ( $self, %args ) = @_;

    #D && $self->log("create(filename=>$args{filename})");
    D && $self->stack;
    if (%args) {
        $self->setCache( exists $args{cache} ? $args{cache} : 1 );
        $self->setCache_dir( $args{cache_dir} );
        if ( defined $args{filename} ) {
            $self->setFilename( $args{filename} );
            D && $self->log( "filename: " . $self->getFilename );
            $self->setPath( $args{path} );
        }
        elsif ( $args{scalarref} || $args{arrayref} ) {
            $args{scalarref} = \( join '', @{ $args{arrayref} } )
              if $args{arrayref};
            $self->setScalar( $args{scalarref} );
            my $text = $self->getScalar;
            my $md5  = Digest::MD5::md5_base64($$text);
            D && $self->log("md5: $md5");
            $self->setFilename($md5);
            #$self->setPath( defined $args{path} ? $args{path} : '' );
            #$self->setPath( $args{path} );
            $self->setPath( '' );
        }
        elsif ( $args{filehandle} ) {
            $self->setFilehandle( $args{filehandle} );
            $self->setCache(0);
        }
    }
    D && $self->log("trying from_cache()");
    my $t = $self->from_cache();
    if ($t) {
        $t = $t->clone;
    }
    D && $self->log(\%args);
    if ($t) {
        if ( my $fm = $args{formatter} || $self->getFormatter ) {
            unless ( $t->getFormatter ) {
                $t->setFormatter($fm);
            }
        }
        if ( my $dumper = $args{dumper} || $self->getDumper ) {
            unless ( $t->getDumper ) {
                $t->setDumper($dumper);
            }
        }
        if ( my $filter = $args{filter} || $self->getFilter ) {
            unless ( $t->getFilter ) {
                $t->setDumper($filter);
            }
        }
    }
    return $t if $t;
    D && $self->log("tried from_cache()");

    #D && $self->log("tried from_cache() filename=".$self->getFilename);
    # ok, seems we have nothing in cache, so compile
    my $fname = $self->getFilename;
    if ( defined $fname and !$self->getScalar and !$self->getFilehandle ) {

        #D && $self->log("tried from_cache() filename=".$fname);
        my $file = $self->createFilename( $self->getPath, $fname );
        D && $self->log("setFile $file ($fname)");
        $self->setFile($file);
    }
    elsif ( defined $fname ) {
        $self->setFile($fname);
    }
    $self->init(%args) if %args;
    D && $self->log( "compiling... " . $self->getFilename );
    $self->compile();
    return $self;
}
sub from_cache {
    my ($self) = @_;
    my $t;
    D && $self->log( "from_cache() filename=" . $self->getFilename );

    # try to get memory cache
    if ( $self->getCache ) {
        $t = $self->from_mem_cache();
        return $t if $t;
    }
    D && $self->log( "from_cache() 2 filename=" . $self->getFilename );

    # not in memory cache, try file cache
    if ( $self->getCache_dir ) {
        $t = $self->include();
        return $t if $t;
    }
    D && $self->log( "from_cache() 3 filename=" . $self->getFilename );
    return;
}

{
    my $cache;
    my $times;

    sub from_mem_cache {
        my ($self) = @_;
        my $dir = $self->getCache_dir;
        $dir = '' unless defined $dir;
        my $fname  = $self->getFilename;
        my $cached = $cache->{$dir}->{$fname};
        my $times  = $times->{$dir}->{$fname};
        D && $self->log("\$cached=$cached \$times=$times \$fname=$fname\n");
        if ( $cached && $self->uptodate($times) ) {
            return $cached;
        }
        D && $self->log("no or old memcache");
        return;
    }
    sub add_mem_cache {
        my ( $self, %times ) = @_;
        D && $self->stack(1);
        my $dir = $self->getCache_dir;
        $dir = '' unless defined $dir;
        my $fname = $self->getFilename;
        D && $self->log( "add_mem_cache " . $fname );
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
        my ( $self, $dir ) = @_;
        defined $dir
          or $dir = $self->getCache_dir;
        return unless -d $dir;
        ref $self and $self->lock;
        opendir my $dh, $dir or die "Could not open '$dir': $!";
        my @files = grep { m/\.pl$/ } readdir $dh;
        for my $file (@files) {
            my $file = File::Spec->catfile( $dir, $file );
            unlink $file or die "Could not delete '$file': $!";
        }
        ref $self and $self->unlock;
        return 1;
    }

    sub uptodate {
        my ( $self, $cached_times ) = @_;
        return 1 if $self->getScalar;
        unless ($cached_times) {
            my $dir = $self->getCache_dir;
            $dir = '' unless defined $dir;
            my $fname  = $self->getFilename;
            my $cached = $cache->{$dir}->{$fname};
            $cached_times  = $times->{$dir}->{$fname};
            return unless $cached;
        }
        my $now = time;
        if ( $now - $cached_times->{checked} < $NEW_CHECK ) {
            return 1;
        }
        else {
            my $file = $self->createFilename( $self->getPath, $self->getFilename );
            $self->setFile($file);
            #print STDERR "uptodate($file)\n";
            my @times = $self->_checktimes($file);
            if ( $times[MTIME] <= $cached_times->{mtime} ) {
                D && $self->log("uptodate template old");
                # set last check time to new value
                $cached_times->{checked} = $now;
                return 1;
            }
        }
        # template is not up to date, re-compile it
        return 0;
    }



}

sub compile {
    my ($self) = @_;
    my ( $source, $compiled );
    if ( my $file = $self->getFile and !$self->getScalar ) {

        # thanks to sam tregars testsuite
        # don't recursively include
        my $recursed = ++$FILESTACK{$file};
        D && $self->log( "compile from file " . $file );
        die "Could not open '$file': $!" unless -f $file;
        my @times = $self->_checktimes($file);
        my $text  = $self->_readfile($file);
        die "HTML::Template: recursive include of " . $file . " $recursed times"
          if $recursed > 10;
        my ( $source, $compiled ) = $self->_compile( $text, $file );
        --$FILESTACK{$file} or delete $FILESTACK{$file};
        $self->setPerl($compiled);
        $self->getCache and $self->add_mem_cache(
            checked => time,
            mtime   => $times[MTIME],
        );
        D && $self->log("compiled $file");

        if ( $self->getCache_dir ) {
            D && $self->log("add_file_cache($file)");
            $self->add_file_cache(
                $source,
                checked => time,
                mtime   => $times[MTIME],
            );
        }
    }
    elsif ( my $text = $self->getScalar ) {
        my $md5 = $self->getFilename;    # yeah, weird
        D && $self->log("compiled $md5");
        my ( $source, $compiled ) = $self->_compile( $$text, $md5 );
        $self->setPerl($compiled);
        if ( $self->getCache_dir ) {
            D && $self->log("add_file_cache($file)");
            $self->add_file_cache(
                $source,
                checked => time,
                mtime   => time,
            );
        }
    }
    elsif ( my $fh = $self->getFilehandle ) {
        local $/;
        my $data = <$fh>;
        my ( $source, $compiled ) = $self->_compile( $data, '' );
        $self->setPerl($compiled);

    }
}
sub add_file_cache {
    my ( $self, $source, %times ) = @_;
    $self->lock;
    my $cache    = $self->getCache_dir;
    my $plfile   = $self->escape_filename( $self->getFile );
    my $filename = $self->getFilename;
    my $lmtime   = localtime $times{mtime};
    my $lchecked = localtime $times{checked};
    D && $self->log("add_file_cache() $cache/$plfile");
    open my $fh, ">$cache/$plfile.pl" or die $!;    # TODO File::Spec
    my $path     = $self->getPath;
    my $path_str = '['
      . (
        ref $path eq 'ARRAY'
        ? ( join ', ', map { $self->quote_file($_) } @$path )
        : $self->quote_file($path)
      )
      . ']';
    my $isScalar = $self->getScalar ? 1 : 0;
    my $query_info = $self->getUse_query;
    $query_info = Data::Dumper->Dump([\$query_info], ['query_info']);
    my $parser =$self->getParser;
    $parser = Data::Dumper->Dump([\$parser], ['parser']);
    my $gl = $self->getGlobal_vars;
    my $file_args = $isScalar
      ? <<"EOM"
        scalarref => $isScalar,
        filename => '@{[$self->getFilename]}',
EOM
      : <<"EOM";
        filename => '@{[$self->getFilename]}',
EOM
    print $fh <<"EOM";
    package HTML::Template::Compiled;
# file date $lmtime
# last checked date $lchecked
my $query_info;
my $parser;
my \$args = {
    # HTC version
    version => '$VERSION',
    times => {
        mtime => $times{mtime},
        checked => $times{checked},
    },
    htc => {
        case_sensitive => @{[$self->getCase_sensitive]},
        cache_dir => '$cache',
$file_args
    path => $path_str,
    formatter_path => '@{[$self->getFormatter_path]}',
    method_call => '@{[$self->getMethod_call]}',
    deref => '@{[$self->getDeref]}',
    out_fh => @{[$self->getOut_fh]},
    default_path   => '@{[$self->getDefault_path]}',
    default_escape => '@{[$self->getDefault_escape]}',
    use_query => \$query_info,
    parser => \$parser,
    global_vars => $gl,
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
    my $file = $self->createFilename( $self->getPath, $self->getFilename );
    D && $self->log("include file: $file");

    #$self->setFile($file);
    my $dir     = $self->getCache_dir;
    my $escaped = $self->escape_filename($file);
    my $req     = File::Spec->catfile( $dir, "$escaped.pl" );
    return unless -f $req;
    return $self->include_file($req);
}

sub include_file {
    my ( $self, $req ) = @_;
    D && $self->log("do $req");
    my $r;
    if ($UNTAINT) {
        # you said explicitly that you can trust your compiled code
        open my $fh, '<', $req or die "Could not open '$req': $!";
        local $/;
        my $code = <$fh>;
        if ( $code =~ m/(\A.*\z)/ms ) {
            $code = $1;
        }
        else {
            $code = "";
        }
        $r = eval $code;
    }
    else {
        $r = do $req;
    }
    if ($@) {
        # we had an error while including
        die "Eror while inclundig '$req': $@";
    }
    my $cached_version = $r->{version};
    my $args = $r->{htc};
    # we first just create from cached perl-code
    my $t = HTML::Template::Compiled->new(%$args);
    unless ($VERSION eq $cached_version && $t->uptodate( $r->{times} )) {
        # is not uptodate
        # print STDERR "$t is not uptodate\n";
        $t->compile;
    }
    # recompile if timestamps have changed or HTC version
    $t->add_mem_cache(
        checked => $r->{times}->{checked},
        mtime   => $r->{times}->{mtime},
    );
    return $t;
}

sub createFilename {
    my ( $self, $path, $filename ) = @_;
    D && $self->log("createFilename($path,$filename)");
    D && $self->stack(1);
    if ( !length $path or File::Spec->file_name_is_absolute($filename) ) {
        return $filename;
    }
    else {
        D && $self->log( "file: " . File::Spec->catfile( $path, $filename ) );
        my $sp = $self->getSearch_path_on_include;
        for (
              ref $path
            ? $sp
            ? @$path
            : $path->[0]
            : $path
          ) {
            my $fp = File::Spec->catfile( $_, $filename );
            return $fp if -f $fp;
        }

        # TODO - bug with scalarref
        croak "'$filename' not found";
    }
}

sub dump {
    my ( $self, $var ) = @_;
    if ( my $sub = $self->getDumper() ) {
        unless ( ref $sub ) {
            # we have a plugin
            $sub =~ tr/0-9a-zA-Z//cd;    # allow only words
            my $class = "HTML::Template::Compiled::Plugin::$sub";
            $sub = \&{ $class . '::dumper' };
        }
        return $sub->($var);
    }
    else {
        require Data::Dumper;
        local $Data::Dumper::Indent   = 1;
        local $Data::Dumper::Sortkeys = 1;
        return Data::Dumper->Dump( [$var], ['DUMP'] );
    }
}

sub init {
    my ( $self, %args ) = @_;
    my %defaults = (

        # defaults
        method_call            => '.',
        deref                  => '.',
        formatter_path         => '/',
        search_path_on_include => $SEARCHPATH,
        loop_context_vars      => 0,
        case_sensitive         => $CASE_SENSITIVE_DEFAULT,
        debug                  => $DEBUG_DEFAULT,
        out_fh                 => 0,
        global_vars            => 0,
        default_escape         => $DEFAULT_ESCAPE,
        default_path           => PATH_DEREF,
        use_query              => $DEFAULT_QUERY,
        %args,
    );
    $self->setMethod_call( $defaults{method_call} );
    $self->setDeref( $defaults{deref} );
    $self->setLoop_context(1) if $args{loop_context_vars};
    $self->setCase_sensitive( $defaults{case_sensitive} );
    $self->setDumper( $args{dumper} )       if $args{dumper};
    $self->setFormatter( $args{formatter} ) if $args{formatter};
    $self->setDefault_escape( $defaults{default_escape} );
    $self->setDefault_path( $defaults{default_path} );
    $self->setUse_query( $defaults{use_query} );
    $self->setSearch_path_on_include( $defaults{search_path_on_include} );
    if ( $args{filter} ) {
        require HTML::Template::Compiled::Filter;
        $self->setFilter(
            HTML::Template::Compiled::Filter->new( $args{filter} ) );
    }
    $self->setDebug( $defaults{debug} );
    $self->setOut_fh( $defaults{out_fh} );
    $self->setGlobal_vars( $defaults{global_vars} );
    $self->setFormatter_path( $defaults{formatter_path} );
    my $tagstyle = $args{tagstyle};
    my $parser;
    if (ref $tagstyle eq 'ARRAY') {
        # user specified named styles or regexes
        $parser = HTML::Template::Compiled::Parser->new(
            tagstyle => $tagstyle,
        );
    }
    elsif (ref $tagstyle eq 'HTML::Template::Compiled::Parser') {
        $parser = $tagstyle;
    }
    $parser ||= HTML::Template::Compiled::Parser->new();
    $self->setParser($parser);
}

sub _readfile {
    my ( $self, $file ) = @_;
    open my $fh, $file or die "Cannot open '$file': $!";
    local $/;
    my $text = <$fh>;
    return $text;
}

sub _compile {
    my ( $self, $text, $fname ) = @_;
    D && $self->log("_compile($fname)");
    if ( my $filter = $self->getFilter ) {
        $filter->filter($text);
    }
    my $parser = $self->getParser;
    my @p = $parser->tags($text);
    my $level = 1;
    my $code  = '';
    my $stack = [T_END];
    my $info = {}; # for query()
    my $info_stack = [$info];

    # got this trick from perlmonks.org
    my $anon = D
      || $self->getDebug ? qq{local *__ANON__ = "htc_$fname";\n} : '';

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
    my \$OUT = '';
    #my \$C = \\\$P;
EOM

    my $line_save = 0;
    my @lexicals;
    my @switches;
    my $comment = 0;
    my $noparse = 0;
    my $verbatim = 0;
    for my $p (@p) {
        my ($text, $tt, $line, $open, $tname, $attr, $close) = @$p;
        #print STDERR "tags: ($text, $tt, $line, $open, $tname, $attr, $close)\n";
        $line_save = $line;
        local $_ = $text;
        s/~/\\~/g;
        #print STDERR "p: '$_'\n";
        my $indent = INDENT x $level;
        my $is_tag = $tt != NO_TAG;
        my $is_open = $is_tag && $tt == OPENING_TAG;
        my $is_close = $is_tag && $tt == CLOSING_TAG;
        my $meth     = $self->getMethod_call;
        my $deref    = $self->getDeref;
        my $format   = $self->getFormatter_path;
        my %var_args = (
            deref          => $deref,
            method_call    => $meth,
            formatter_path => $format,
            lexicals       => \@lexicals,
            final          => 0,   
        );
        # --------- TMPL_VAR
        if ( !$comment && !$noparse && !$verbatim) {
            if ($is_open && $tname eq T_VAR && exists $attr->{NAME}) {
                #print STDERR "===== VAR ($_)\n";
                my $type = $tname;
                my $var = $attr->{NAME};
                if ($self->getUse_query) {
                    $info_stack->[-1]->{lc $var}->{type} = T_VAR;
                }
                my $escape = $self->getDefault_escape;
                if (exists $attr->{ESCAPE}) {
                    $escape = $attr->{ESCAPE};
                }
                my $default;
                if (exists $attr->{DEFAULT}) {
                    $default = $attr->{DEFAULT};
                    my $exp = _expr_string($default);
                    $default = $exp->to_string($level);
                }
                my $varstr = $self->_make_path(
                    %var_args,
                    var   => $var,
                    final => 1,
                );

                #print "line: $_ var: $var ($varstr)\n";
                my $root = 0;
                if ( $var =~ s/^\.// ) {
                    # we have NAME=.ROOT
                    $root++;
                }
                if ( $root ) {
                    $code .= qq#${indent}\{\n${indent}  my \$C = \$C;\n#;
                    $code .= qq#${indent}  \$C = \\\$P;\n#;
                }
                my $exp = _expr_literal($varstr);
                if ( defined $default ) {
                    $exp = _expr_ternary(
                        _expr_defined($exp),
                        $exp,
                        _expr_literal($default),
                    );
                }
                $exp = $self->_escape_expression($exp, $escape);
                $code .= qq#${indent}$output #
                    . $exp->to_string($level) . qq#;\n#;
                if ( $root ) {
                    $code .= _expr_close()->to_string($level);
                }
            }
            # --------- TMPL_WITH
            elsif ($is_open && $tname eq T_WITH && exists $attr->{NAME}) {
                push @$stack, T_WITH;
                $level++;
                my $var    = $attr->{NAME};
                my $varstr = $self->_make_path(
                    %var_args,
                    var => $var,
                );
                $code .= qq#${indent}\{ \# WITH $var\n#;
                if ($self->getGlobal_vars) {
                    $code .= _expr_method(
                        'pushGlobalstack',
                        _expr_literal('$t'),
                        _expr_literal('$$C')
                    )->to_string($level) . ";\n";
                }
                $code .= qq#${indent}  my \$C = \\$varstr;\n#;
            }

            # --------- TMPL_LOOP_CONTEXT
            elsif ($is_open && $tname eq T_LOOP_CONTEXT) {
                my $indent = INDENT x $level;
                $code .= <<"EOM";
${indent}local \$__counter__ = \$ix+1;
${indent}local \$__first__   = \$ix == \$[;
${indent}local \$__last__    = \$ix == \$size;
${indent}local \$__odd__     = !(\$ix & 1);
${indent}local \$__inner__   = !\$__first__ && !\$__last__;
EOM
            }

            # --------- TMPL_LOOP|WHILE
            elsif ($is_open && ($tname eq T_LOOP || $tname eq T_WHILE)
                && exists $attr->{NAME}) {
                push @$stack, $tname;
                my $var     = $attr->{NAME};
                my $varstr = $self->_make_path(
                    %var_args,
                    var   => $var,
                );
                $level += 2;
                my $ind    = INDENT;
                if ($self->getUse_query) {
                    $info_stack->[-1]->{lc $var}->{type} = T_LOOP;
                    $info_stack->[-1]->{lc $var}->{children} ||= {};
                    push @$info_stack, $info_stack->[-1]->{lc $var}->{children};
                }
                my $lexical = $attr->{ALIAS};
                push @lexicals, $lexical;
                my $lexi =
                  defined $lexical ? "${indent}my \$$lexical = \$\$C;\n" : "";
                if ($tname eq T_WHILE) {
                    $code .= <<"EOM";
${indent}${ind}# while $var
${indent}${ind}\{
${indent}${ind}while (my \$next = $varstr) {
${indent}${indent}my \$C = \\\$next;
EOM
                }
                else {
                    my $global = $self->getGlobal_vars ? <<"EOM" : '';
${indent}\$t->pushGlobalstack(\$\$C);
EOM
                    $code .= <<"EOM";
${indent}if (UNIVERSAL::isa(my \$array = $varstr, 'ARRAY') )\{
${indent}${ind}my \$size = \$#{ \$array };
$global

${indent}${ind}# loop over $var
${indent}${ind}for my \$ix (\$[..\$size) \{
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
            }

            # --------- TMPL_ELSE
            elsif ($is_open && $tname eq T_ELSE) {
                $self->_checkstack( $fname, $line, $stack, T_ELSE );
                pop @$stack;
                push @$stack, T_ELSE;
                my $exp = HTML::Template::Compiled::Expression::Else->new;
                $code .= $exp->to_string($level);
            }

            # --------- / TMPL_IF TMPL UNLESS TMPL_WITH
            elsif ($is_close && $tname =~ m/^(?:IF|UNLESS|WITH)$/) {
                my $var = $attr->{NAME};
                $var = '' unless defined $var;
                #print STDERR "============ IF ($_)\n";
                $self->_checkstack( $fname, $line, $stack, $tname );
                pop @$stack;
                $level--;
                my $indent = INDENT x $level;
                my $exp = HTML::Template::Compiled::Expression::Close->new;
                $code .= $exp->to_string($level) . qq{# end $var\n};
                if ($self->getGlobal_vars && $tname eq 'WITH') {
                    $code .= $indent . qq#\$t->popGlobalstack;\n#;
                }
            }

			# --------- / TMPL_LOOP
            elsif ($is_close && ($tname eq T_LOOP || $tname eq T_WHILE)) {
                $self->_checkstack($fname,$line,$stack, $tname);
                pop @$stack;
                pop @lexicals;
                if ($self->getUse_query) {
                    pop @$info_stack;
                }
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
			# --------- TMPL_IF TMPL_UNLESS TMPL_ELSIF
            elsif ($is_open && $tname =~ m/^(?:IF_DEFINED|IF DEFINED|IF|UNLESS|ELSIF)$/ && exists $attr->{NAME}) {
                #print STDERR "============ IF ($_)\n";
                my $def    = $tname =~ m/DEFINED$/;
                if ($tname eq 'IF DEFINED') {
                    carp "use of TMPL_IF DEFINED is deprecated. use TMPL_IF_DEFINED instead";
                }
                my $var    = $attr->{NAME};
                my $varstr = $self->_make_path(
                    %var_args,
                    var   => $var,
                );
                my $if = {
                    IF => 'If',
                    UNLESS => 'Unless',
                    ELSIF => 'Elsif',
                    IF_DEFINED => 'If',
                    'IF DEFINED' => 'If',
                }->{ $tname };
                my $operand = HTML::Template::Compiled::Expression::Literal->new($varstr);
                my $eclass = "HTML::Template::Compiled::Expression::$if";
                my $elsif = $tname eq 'ELSIF' ? 1 : 0;
                if ($def) {
                    $operand = HTML::Template::Compiled::Expression::Defined->new($operand);
                }
                if ($elsif) {
                    $self->_checkstack( $fname, $line, $stack, $tname );
                }
                else {
                    push @$stack, $tname;
                    $level++;
                }
                my $exp = $eclass->new($operand);
                my $str = $exp->to_string($level);
                $code .= $str . $/;
            }

            # --------- TMPL_SWITCH
            elsif ( $is_open && $tname eq T_SWITCH && exists $attr->{NAME}) {
                my $var = $attr->{NAME};
                push @$stack,   T_SWITCH;
                push @switches, 0;
                $level++;
                my $varstr = $self->_make_path(
                    %var_args,
                    var   => $var,
                );
                $code .= <<"EOM";
${indent}SWITCH: for my \$_switch ($varstr) \{
EOM
            }
            
            # --------- / TMPL_SWITCH
            elsif ($is_close && $tname eq T_SWITCH) {
                $self->_checkstack( $fname, $line, $stack, T_SWITCH );
                pop @$stack;
                $level--;
                if ( $switches[$#switches] ) {

                    # we had at least one CASE, so we close the last if
                    $code .= qq#${indent}\} \# last case\n#;
                }
                $code .= qq#${indent}\}\n#;
                pop @switches;
            }
            
            # --------- TMPL_CASE
            elsif ($is_open && $tname eq T_CASE) {
                my $val = $attr->{NAME};
                #$val =~ s/^\s+//;
                $self->_checkstack( $fname, $line, $stack, T_CASE );
                if ( $switches[$#switches] ) {

                    # we aren't the first case
                    $code .= qq#${indent}last SWITCH;\n${indent}\}\n#;
                }
                else {
                    $switches[$#switches] = 1;
                    $level++;
                }
                if ( !length $val or uc $val eq 'DEFAULT' ) {
                    $code .= qq#${indent}if (1) \{\n#;
                }
                else {
                    my @splitted = split ",", $val;
                    my $is_default = '';
                    @splitted = grep {
                        uc $_ eq 'DEFAULT'
                            ? do {
                                $is_default = ' or 1 ';
                                0;
                            }
                            : 1
                    } @splitted;
                    my $values = join ",", map { qq#'$_'# } @splitted;
                    $code .=
qq#${indent}if (grep \{ \$_switch eq \$_ \} $values $is_default) \{\n#;
                }
            }

            # --------- TMPL_INCLUDE_VAR
            elsif ($is_open && $tname =~ m/^INCLUDE/ && exists $attr->{NAME}) {
                my $filename;
                my $varstr;
                my $path = $self->getPath();
                my $dir;
                $path = [$path] unless ref $path eq 'ARRAY';
                my $dynamic = $tname eq T_INCLUDE_VAR ? 1 : 0;

                if ($dynamic) {
                    # dynamic filename
                    my $dfilename = $attr->{NAME};
                    $varstr = $self->_make_path(
                        %var_args,
                        var   => $dfilename,
                    );
                }
                else {
                    # static filename
                    $filename = $attr->{NAME};
                    $varstr   = $self->quote_file($filename);
                    $dir      = dirname $fname;
                    if ( defined $dir and !grep { $dir eq $_ } @$path ) {
                        # add the current directory to top of paths
                        $path =
                          [ $dir, @$path ]
                          ;    # create new $path, don't alter original ref
                    }
                    # generate included template
                    {
                        D && $self->log("compile include $filename!!");
                        my $cached_or_new =
                          $self->clone_init( $path, $filename,
                            $self->getCache_dir );
                    }
                }
                #print STDERR "include $varstr\n";
                my $cache = $self->getCache_dir;
                $path = defined $path
                  ? !ref $path
                  ? $self->quote_file($path)

                  # support path => arrayref soon
                  : '['
                  . join( ',', map { $self->quote_file($_) } @$path ) . ']'
                  : 'undef';
                $cache =
                  defined $cache ? $self->quote_file($cache) : 'undef';
                $code .= <<"EOM";
${indent}\{
${indent}  if (defined (my \$file = $varstr)) \{
${indent}    my \$new = \$t->clone_init($path,\$file,$cache);
${indent}    $output \$new->getPerl()->(\$new,\$P,\$C@{[$out_fh ? ",\$OFH" : '']});
${indent}  \}
${indent}\}
EOM
            }

            # --------- TMPL_COMMENT|NOPARSE|VERBATIM
            elsif ($is_open && $tname =~ m/^(?:COMMENT|NOPARSE|VERBATIM)$/) {
                my $name = $attr->{NAME};
                $name = '' unless defined $name;
                $tname eq 'COMMENT' ? $comment++ : $tname eq 'NOPARSE' ? $noparse++ : $verbatim++;
                $code .= qq{ # comment $name (level $comment)\n};
            }

            # --------- / TMPL_COMMENT|NOPARSE|VERBATIM
            elsif ($is_close && $tname =~ m/^(?:COMMENT|NOPARSE|VERBATIM)$/) {
                my $name = $attr->{NAME};
                $name = '' unless defined $name;
                $code .= qq{ # end comment $name (level $comment)\n};
                $tname eq 'COMMENT' ? $comment-- : $tname eq 'NOPARSE' ? $noparse-- : $verbatim--;
            }
            else {
                if ( length $_ ) {
                    my $exp = HTML::Template::Compiled::Expression::String->new($_);
                    $code .= qq#$indent$output # . $exp->to_string($level) . $/;
                }
            }
        }
        else {

            # --------- TMPL_COMMENT|NOPARSE|VERBATIM
            if ($is_open && $tname =~ m/^(?:COMMENT|NOPARSE|VERBATIM)$/) {
                my $name = $attr->{NAME};
                $name = '' unless defined $name;
                $tname eq 'COMMENT' ? $comment++ : $tname eq 'NOPARSE' ? $noparse++ : $verbatim++;
                $code .= qq{ # comment $name (level $comment)\n};
            }

            # --------- / TMPL_COMMENT|NOPARSE|VERBATIM
            elsif ($is_close && $tname =~ m/^(?:COMMENT|NOPARSE|VERBATIM)$/) {
                my $name = $attr->{NAME};
                $name = '' unless defined $name;
                $code .= qq{ # end comment $name (level $comment)\n};
                $tname eq 'COMMENT' ? $comment-- : $tname eq 'NOPARSE' ? $noparse-- : $verbatim--;
            }
            else {
                # don't output anything if we are in a comment
                # but output if we are in noparse or verbatim
                if ( !$comment && length $_ ) {
                    if ($verbatim) {
                        HTML::Entities::encode_entities($_);
                    }
                    my $exp = HTML::Template::Compiled::Expression::String->new($_);
                    $code .= qq#$indent$output # . $exp->to_string($level) . $/;
                }
            }
        }
    }
    $self->_checkstack( $fname, $line_save, $stack, T_END );
    if ($self->getUse_query) {
        $self->setUse_query($info);
    }
    #warn Data::Dumper->Dump([\$info], ['info']);
    $code .= qq#return \$OUT;\n#;
    $code = $header . $code . "\n} # end of sub\n";

    #$code .= "\n} # end of sub\n";
    print STDERR "# ----- code \n$code\n# end code\n" if $self->getDebug;

    # untaint code
    if ( $code =~ m/(\A.*\z)/ms ) {
        # we trust our template
        $code = $1;
    }
    else {
        $code = "";
    }
    my $sub = eval $code;
    die "code: $@" if $@;
    return $code, $sub;
}

sub _escape_expression {
    my ($self, $exp, $escape) = @_;
    return $exp unless $escape;
    my @escapes = split m/\|/, uc $escape;
    for (@escapes) {
        if ( $_ eq 'HTML' ) {
            $exp = HTML::Template::Compiled::Expression::Function->new(
                'HTML::Template::Compiled::Utils::escape_html',
                $exp,
            );
        }
        elsif ( $_ eq 'URL' ) {
            $exp = HTML::Template::Compiled::Expression::Function->new(
                'HTML::Template::Compiled::Utils::escape_uri',
                $exp,
            );
        }
        elsif ( $_ eq 'JS' ) {
            $exp = HTML::Template::Compiled::Expression::Function->new(
                'HTML::Template::Compiled::Utils::escape_js',
                $exp,
            );
        }
        elsif ( $_ eq 'DUMP' ) {
            $exp = HTML::Template::Compiled::Expression::Method->new(
                'dump',
                HTML::Template::Compiled::Expression::Literal->new('$t'),
                $exp,
            );
        }
    }
    return $exp;
}

sub quote_file {
    my $f = $_[1];
    $f =~ s/'/\\'/g;
    return qq/'$f'/;
}

# this method gets a varname like 'var' or 'object.method'
# or 'hash.key' and makes valid perl code out of it that will
# be eval()ed later
# so assuming . is the character for dereferencing hashes the string
# hash.key (found inside <tmpl_var name="hash.key">) will be converted to
# '$t->get_var($P, $$C, 1, [PATH_DEREF, 'key'])'
# the get_var method walks the paths given through the data structure.
# $P is the paramater hash of the template, $C is a reference to the current
# parameter hash. the third argument to get_var is 'final'.
# <tmpl_var foo> is a 'final' path, and <tmpl_with foo> is not.
# so final means it's in 'print-context'.
sub _make_path {
    my ( $self, %args ) = @_;
    my $lexicals = $args{lexicals};
    my $local_loop_context = 0;
    if ( grep { defined $_ && $args{var} eq $_ } @$lexicals ) {
        return "\$$args{var}";
    }
    my $root = 0;
    if ( $self->getLoop_context && $args{var} =~ m/^__(\w+)__$/ ) {
        return "\$\L$args{var}\E";
    }
    elsif ( $args{var} =~ m/^__(\w+)__$/ ) {
        $local_loop_context = 1;
    }
    elsif ( $args{var} =~ s/^_// ) {
        $root = 0;
    }
    elsif ($args{var} =~ m/^(\Q$args{deref}\E|\Q$args{method_call}\E|\Q$args{formatter_path}\E)(\1?)/) {
        $root = 1 unless length $2;
    }
    my @split = split m/(?=\Q$args{deref}\E|\Q$args{method_call}\E|\Q$args{formatter_path}\E)/, $args{var};
    my @paths;
    for my $p (@split) {
        if ( $p =~ s/^\Q$args{method_call}// ) {
            push @paths, '[' . PATH_METHOD . ",'$p']";
        }
        elsif ($p =~ s/^\Q$args{deref}//) {
            push @paths, '['.PATH_DEREF.",'".($self->getCase_sensitive?$p:uc$p)."']";
        }
        elsif ($p =~ s/^\Q$args{formatter_path}//) {
            push @paths, '['.PATH_FORMATTER.",'".($self->getCase_sensitive?$p:uc$p)."']";
        }
        else {
            push @paths, '['. $self->getDefault_path() .", '".($self->getCase_sensitive?$p:uc$p)."']";
        }
    }
    local $" = ",";
    my $final = $args{final} ? 1 : 0;
    my $getvar = $ENABLE_SUB ? '_get_var_sub' : '_get_var';
    $getvar .= $self->getGlobal_vars&1 ? '_global' : '';
    my $varstr =
      "\$t->$getvar(\$P," . ( $root ? '$P' : '$$C' ) . ",$final,@paths)";
    if ($local_loop_context) {
        return "defined \$\L$args{var}\E ? \$\L$args{var}\E : $varstr";
    }
    else {
        return $varstr;
    }
}


# -------- warning, ugly code
# i'm trading maintainability for efficiency here

sub try_global {
    my ( $self, $walk, $path ) = @_;
    my $stack = $self->getGlobalstack || [];
    #warn Data::Dumper->Dump([\$stack], ['stack']);
    for my $item ( $walk, reverse @$stack ) {
        if (my $code = UNIVERSAL::can($item, $path)) {
            my $r =  $code->($item);
            return $r;
        }
        else {
            next unless exists $item->{$path};
            return $item->{$path};
        }
    }
    return;
}

{
	# ----------- still ugly code
	# generating different code depending on global_vars
	my $code = <<'EOM';
sub {
	my ($self, $P, $ref, $final, @paths) = @_;
	my $walk = $ref;
    # H::T compatibility
    my $literal_dot = join '.', map { $_->[1] } @paths;
    return $walk->{$literal_dot} if ref $walk eq 'HASH' and exists $walk->{$literal_dot};

	for my $path (@paths) {
        last unless defined $walk;
        #print STDERR "ref: $walk, key: $path->[1]\n";
		if ($path->[0] == PATH_DEREF || $path->[0] == PATH_METHOD) {
			if (ref $walk eq 'ARRAY') {
				$walk = $walk->[$path->[1]];
			}
			else {
                unless (length $path->[1]) {
                    my $stack = $self->getGlobalstack || [];
                    # we have tmpl_var ..foo, get one level up the stack
                    $walk = $stack->[-1];
                }
                else {
*** walk ***
                }
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
    if (my $formatter = $self->getFormatter() and $final and my $ref = ref $walk) {
        if (my $sub = $formatter->{$ref}->{''}) {
            my $return = $sub->($walk,$self,$P);
            return $return unless ref $return;
        }
    }
	return $walk;
}
EOM
	my $global = <<'EOM';
	$walk = $self->try_global($walk, $path->[1]);
EOM
	my $walk = <<'EOM';
    #$walk = $walk->{$path->[1]};
    if (UNIVERSAL::can($walk, 'can')) {
        my $method = $path->[1];
        $walk = $walk->$method;
    }
    else {
        $walk = $walk->{$path->[1]};
    }
EOM
	my $sub = $code;
	$sub =~ s/^\Q*** walk ***\E$/$walk/m;
	my $subref = eval $sub;
    die "Compiling _get_var: $@" if $@;
	no strict 'refs';
	*{'HTML::Template::Compiled::_get_var'} = $subref;
	$sub = $code;
	$sub =~ s/^\Q*** walk ***\E$/$global/m;
	$subref = eval $sub;
    die "Compiling _get_var_global: $@" if $@;
	*{'_get_var_global'} = $subref;
}

# and another two ugly subroutines

sub _get_var_sub {
    my ( $self, $P, $ref, $final, @paths ) = @_;
    my $var = $self->_get_var( $P, $ref, $final, @paths );
    if ( $ENABLE_SUB and ref $var eq 'CODE' ) {
        return $var->();
    }
    return $var;
}
sub _get_var_sub_global {
    my ( $self, $P, $ref, $final, @paths ) = @_;
    my $var = $self->_get_var_global( $P, $ref, $final, @paths );
    if ( $ENABLE_SUB and $final and ref $var eq 'CODE' ) {
        return $var->();
    }
    return $var;
}

# end ugly code, phooey

{
    my %map = (
        IF         => [ T_IF, T_UNLESS, T_ELSE ],
        UNLESS     => [T_UNLESS, T_ELSE, T_IF_DEFINED],
        ELSIF      => [ T_IF, T_UNLESS, T_IF_DEFINED ],
        ELSE       => [ T_IF, T_UNLESS, T_ELSIF, T_IF_DEFINED ],
        LOOP       => [T_LOOP],
        WHILE      => [T_WHILE],
        WITH       => [T_WITH],
        T_SWITCH() => [T_SWITCH],
        T_CASE()   => [T_SWITCH],
        T_END()    => [T_END],
    );

    sub _checkstack {
        my ( $self, $fname, $line, $stack, $check ) = @_;

        # $self->stack(1);
        my @allowed = @{ $map{$check} };
        return 1 if @$stack == 0 and @allowed == 0;
        die
"Closing tag 'TMPL_$check' does not have opening tag at $fname line $line\n"
          unless @$stack;
        if ( $allowed[0] eq T_END and $stack->[-1] ne T_END ) {

         # we hit the end of the template but still have an opening tag to close
            die
"Missing closing tag for '$stack->[-1]' at end of $fname line $line\n";
        }
        for (@allowed) {
            return 1 if $_ eq $stack->[-1];
        }
        croak
"'TMPL_$check' does not match opening tag ($stack->[-1]) at $fname line $line\n";
    }
}

sub escape_filename {
    my ( $t, $f ) = @_;
    $f =~ s#([/:\\])#'%'.uc sprintf"%02x",ord $1#ge;
    return $f;
}

sub _checktimes {
    my $self = shift;
    D && $self->stack;
    my $filename = shift;
    my $mtime    = ( stat $filename )[9];

    #print STDERR "stat $filename = $mtime\n";
    my $checked  = time;
    my $lmtime   = localtime $mtime;
    my $lchecked = localtime $checked;
    return ( $mtime, $checked, $lmtime, $lchecked );
}

sub clone {
    my ($self) = @_;
    return bless [@$self], ref $self;
}

sub clone_init {
    my ( $self, $path, $filename, $cache ) = @_;
    unless (defined $filename) {
#        return;
        my ($file) = (caller(1))[3];
        croak "Filename is undef (in template $file)" unless defined $filename;
    }
    my $new = bless [@$self], ref $self;
    D && $self->log("clone_init($path,$filename,$cache)");
    $new->setFilename($filename);
    $new->setScalar();
    $new->setFilehandle();
    $new->setPath($path);
    $new = $new->create();
    my $stack = $self->getGlobalstack || [];
    $new->setGlobalstack($stack);
    $new;
}

sub preload {
    my ( $class, $dir ) = @_;
    opendir my $dh, $dir or die "Could not open '$dir': $!";
    my @files = grep { m/\.pl$/ } readdir $dh;
    closedir $dh;
    my $loaded = 0;
    for my $file (@files) {
        my $success = $class->include_file( File::Spec->catfile( $dir, $file ) );
        $loaded++ if $success;
    }
    return scalar $loaded;
}

sub precompile {
    my ($class, %args) = @_;
    my $files = delete $args{filenames};
    return unless ref $files eq 'ARRAY';
    my @precompiled;
    for my $file (@$files) {
        my $htc = $class->new(%args,
            (ref $file eq 'SCALAR'
                ? 'scalarref'
                : ref $file eq 'ARRAY'
                ? 'arrayref'
                : ref $file eq 'GLOB'
                ? 'filehandle'
                : 'filename') => $file,
        );
        push @precompiled, $htc,
    }
    return \@precompiled;
}

sub clear_params {
    $_[0]->[PARAM] = ();
}
sub param {
    my $self = shift;
    if (!@_) {
        return $self->query();
        return UNIVERSAL::can($self->[PARAM],'can')
            ? $self->[PARAM]
            : $self->[PARAM]
                ? keys %{$self->[PARAM]}
                : ();
    }
    my %p;
    if (@_ == 1) {
        if ( ref $_[0] ) {
            # feed a hashref or object
            if (ref $_[0] eq 'HASH') {
                # hash, no object
                %p = %{ $_[0] };
            }
        }
        else {
            # query a parameter
            return $self->[PARAM]->{ $_[0] };
        }
    }
    else {
        %p = @_;
    }

    if ( !$self->getCase_sensitive ) {
        my $uc = $self->uchash( {%p} );
        %p = %$uc;
    }
    $self->[PARAM]->{$_} = $p{$_} for keys %p;
}

sub query {
    my ($self, $what, $tags) = @_;
    # param() no arguments should behave like query
    # query() is not activated by default, and
    # my %param = (); $htc->param(%param); should
    # *not* call query(). so we check if the user wants
    # a return value; that indicates that they wanted to
    # use query-like behaviour.
    return unless defined wantarray();
    #print STDERR "query(@_)\n";
    my $info = $self->getUse_query
        or carp "You are using query() but have not specified that you want to use it";
    my $pointer = {children => $info};
    $tags = [] unless defined $tags;
    $tags = [$tags] unless ref $tags eq 'ARRAY';
    for my $tag (@$tags) {
        if (defined (my $value = $pointer->{children}->{lc $tag})) {
            $pointer = $value;
        }
    }
    unless ($what) {
        return keys %{ $pointer->{children} };
    }
    elsif ($what eq 'name') {
        my $type = $pointer->{type};
        return $type;
    }
    elsif ($what eq 'loop') {
        if ($pointer->{type} eq 'LOOP') {
            return keys %{ $pointer->{children} };
        }
        else { croak "error: (@$tags) is not a LOOP" }
    }
    return;
}

# =head2 uchash
# 
#   my $capped_href = $self->uchash(\%href);
# 
# Input:
#     - hashref or arrayref of hashrefs
# 
# Output: Returns a reference to a cloned data structure where all the keys are
# capped. 
# 
# =cut

sub uchash {
    my ( $self, $data ) = @_;
    my $uc;
    if ( ref $data eq 'HASH' ) {
        for my $key ( keys %$data ) {
            my $uc_key = uc $key;
            my $val    = $self->uchash( $data->{$key} );
            $uc->{$uc_key} = $val;
        }
    }
    elsif ( ref $data eq 'ARRAY' ) {
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
    my ( $self, $fh ) = @_;
    my $p = $self->[PARAM] || {};
    # if we only have an object as parameter
    $p = ref $p eq 'HASH'
        ? \% { $p }
        : $p;
    my $f = $self->getFile;
    $fh = \*STDOUT unless $fh;
    $self->getPerl()->( $self, $p, \$p, $fh );
}

sub import {
    my ( $class, %args ) = @_;
    if ( $args{compatible} ) {
        $class->EnableSub(1);
        $class->CaseSensitive(0);
        $class->SearchPathOnInclude(0);
        $class->UseQuery(1);
    }
    elsif ( $args{speed} ) {
        # default at the moment
        $class->EnableSub(0);
        $class->CaseSensitive(1);
        $class->SearchPathOnInclude(1);
        $class->UseQuery(0);
    }
}

sub ExpireTime {
    my ($class, $seconds) = @_;
    $NEW_CHECK = $seconds;
}

sub EnableSub {
    my ($class, $bool) = @_;
    $ENABLE_SUB = $bool ? 1 : 0;
}

sub CaseSensitive {
    my ($class, $bool) = @_;
    $CASE_SENSITIVE_DEFAULT = $bool ? 1 : 0;
}

sub SearchPathOnInclude {
    my ($class, $bool) = @_;
    $SEARCHPATH = $bool ? 1 : 0;
}

sub UseQuery {
    my ($class, $bool) = @_;
    $DEFAULT_QUERY = $bool ? 1 : 0;
}

sub pushGlobalstack {
    my $stack = $_[0]->getGlobalstack;
    push @$stack, $_[1];
    $_[0]->setGlobalstack($stack);
}

sub popGlobalstack {
    my $stack = $_[0]->getGlobalstack;
    pop @$stack;
    $_[0]->setGlobalstack($stack);
}


{
    my $lock_fh;

    sub lock {
        my $file = File::Spec->catfile( $_[0]->getCache_dir, "lock" );
        unless ( -f $file ) {
            # touch
            open $lock_fh, '>', $file
              or croak "Could not open lockfile '$file' for writing: $!";
            close $lock_fh;
        }
        open $lock_fh, '+<', $file
          or croak "Could not open lockfile '$file' for read/write: $!";
        flock $lock_fh, LOCK_EX;
    }

    sub unlock {
        close $lock_fh;
    }
}

sub __test_version {
    my $v = __PACKAGE__->VERSION;
    return 1 if $version_pod =~ m/VERSION.*\Q$v/;
    return;
}



1;

__END__

=pod

=head1 SYNOPSIS

  use HTML::Template::Compiled speed => 1;
  # or for compatibility with HTML::Template
  # use HTML::Template::Compiled compatible => 1;
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
template syntax as HTML::Template and the same perl API (see L<"COMPATIBILITY">
for what you need to know if you want the same behaviour). Internally
it works different, because it turns the template into perl code,
and once that is done, generating the output is much faster than with
HTML::Template (3-7 times at the moment, at least with my tests, and 3.5 times (see
L<"Benchmarks"> for some examples), when both are run with loop_context_vars 0. See
L<"TMPL_LOOP_CONTEXT"> for a special feature). It also can generate perl files so that
the next time the template is loaded it doesn't have to be parsed again. The best
performance gain is probably reached in applications running under mod_perl, for example.

If you don't use caching at all (e.g. CGI environment without file caching), HTC
will be even slower than H::T (but still a bit faster than Template-Toolkit.
See the C<examples/bench.pl>.

HTC will use a lot of memory because it keeps all template objects in memory.
If you are on mod_perl, and have a lot of templates, you should preload them at server
startup to be sure that it is in shared memory. At the moment HTC is not fully tested for
keeping all data in shared memory (e.g. when a copy-on-write occurs), but i'll test
that soon. It seems like it's behaving well, but still no guarantee.
For preloading you can now use
  HTML::Template::Compiled->preload($dir).

HTC does not implement all features of HTML::Template (yet), and
it has got some additional features which are explained below.

HTC will complain if you have a closing tag that does not fit
the last opening tag.

Generating code, writing it on disk and later eval() it can open security holes, for example
if you have more users on the same machine that can access the same files (usually an
http server running as 'www' or 'nobody'). See L<"SECURITY"> for details what you can
do to safe yourself.

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

=item ESCAPE=(HTML|URL|JS|0)

=item DEFAULT=...

=item C<__first__>, C<__last__>, C<__inner__>, C<__odd__>, C<__counter__>

=item <!-- TMPL_VAR NAME=PARAM1 -->

=item case insensitive var names

use option case_sensitive => 0 to use this feature (slow down)

=item filters

=item vars that are subrefs

=item scalarref, arrayref, filehandle

=item C<global_vars>

=item C<query>

=back

=head2 ADDITIONAL FEATURES

=over 4

=item TMPL_ELSIF

=item TMPL_WITH

see L<"TMPL_WITH">

=item TMPL_WHILE

see L<"TMPL_WHILE">

=item TMPL_COMMENT

see L<"TMPL_COMMENT">

=item TMPL_NOPARSE

see L<"TMPL_NOPARSE">

=item TMPL_VERBATIM

see L<"TMPL_VERBATIM">

=item TMPL_LOOP_CONTEXT

turn on loop_context in template, see L<"TMPL_LOOP_CONTEXT">

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

Deprecated, use C<TMPL_IF_DEFINED>

=item TMPL_IF_DEFINED

Check for definedness instead of truth:
  <TMPL_IF_DEFINED NAME="var">

=item ALIAS

Set an alias for a loop variable. For example, these two loops are
functionally equivalent:

 <tmpl_loop foo>
   <tmpl_var _>
 </tmpl_loop foo>
 <tmpl_loop foo alias=current>
   <tmpl_var current>
 </tmpl_loop foo>

This works only with C<TMPL_LOOP> at the moment. I probably will
implement this for C<TMPL_WITH>, C<TMPL_WHILE> too.

=item asp/jsp-like templates

For those who like it (i like it because it is shorter than TMPL_), you
can use E<lt>% %E<gt> tags and the E<lt>%= tag instead of E<lt>%VAR (which will work, too):

 <%IF blah%>  <%= VARIABLE%>  <%/IF%>

=item Chained escaping

See L<"ESCAPING">

=back

=head2 MISSING FEATURES

There are some features of H::T that are missing.
I'll try to list them here.

=over 4

=item C<die_on_bad_params>

I don't think I'll implement that.

=back

=head2 COMPATIBILITY

=head3 Same behaviour as HTML::Template

At the moment there are four defaults that differ from L<HTML::Template>:

=over 4

=item case_sensitive

default is 1 (on). Set it via
    HTML::Template::Compiled->CaseSensitive(0);

Note (again): this will slow down templating a lot (50%).

Explanation: This has nothing to do with C<TMPL_IF> or C<tmpl_if>. It's
about the variable names. With case_sensitive set to 1, the following
tags are different:

    <tmpl_var Foo> prints the value of hash key 'Foo'
    <tmpl_var fOO> prints the value of hash key 'fOO'

With case_sensitive set to 0, all your parameters passed to C<param()>
are converted to uppercase, and the following tags are the same:

    <tmpl_var Foo> prints the value of hash key 'FOO'
    <tmpl_var fOO> prints the value of hash key 'FOO'


=item subref variables

default is 0 (off). Set it via
    HTML::Template::Compiled->EnableSub(1);

=item search_path_on_include

default is 1 (on). Set it via
    HTML::Template::Compiledi->SearchPathOnInclude(0);

=item use_query

default is 0 (off). Set it via
    HTML::Template::Compiled->UseQuery(1);

=back

To be compatible in all of the above options all use:

  use HTML::Template::Compiled compatible => 1;

If you don't care about these options you should use

  use HTML::Template::Compiled speed => 1;

which is the default but depending on user wishes that might change.

=head3 Different behaviour from HTML::Template

At the moment this snippet

  <tmpl_if arrayref>true<tmpl_else>false</tmpl_if arrayref>

with this code:

    $htc->param(arrayref => []);

will print true in HTC and false in HTML::Template. In HTML::Template an
array is true if it has content, in HTC it's true if it (the reference) is
defined. I'll try to find a way to change that behaviour, though that might
be for the cost of speed.

=head2 ESCAPING

Like in HTML::Template, you have C<ESCAPE=HTML>, C<ESCAPE=URL> and C<ESCAPE_JS>.
(C<ESCAPE=1> won't follow!  It's old and ugly...)
Additionally you have C<ESCAPE=DUMP>, which by default will generate a Data::Dumper output.
You can change that output by setting a different dumper function, see L<"OPTIONS"> dumper.

You can also chain different escapings, like C<ESCAPE=DUMP|HTML>.

=head2 INCLUDE

Additionally to

  <TMPL_INCLUDE NAME="file.htc">

you can do an include of a template variable:

  <TMPL_INCLUDE_VAR NAME="file_include_var">
  $htc->param(file_include_var => "file.htc");

Using C<INCLUDE VAR="..."> is deprecated.
  
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

This is still in development, so I might change the API here.

Additionally to feeding a simple hash do HTC, you can feed it objects.
To do method calls you can also use '.' in the template or define a different string
if you don't like that.

  my $htc = HTML::Template::Compiled->new(
    ...
    method_call => '.', # default .
  );

  $htc->param(
    VAR => "blah",
    OBJECT => bless({...}, "Your::Class"),
  );

  <TMPL_VAR NAME="OBJECT.fullname">
  <TMPL_WITH OBJECT>
  Name: <TMPL_VAR fullname>
  </TMPL_WITH>

C<fullname> will call the fullname method of your Your::Class object.

It's recommended to just use the default . value for methods and dereferencing.

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

If you have a deep leveled hash you might not want to always write 
THE.FULL.PATH.TO.YOUR.VAR. Jump to your desired level once and
then you need only one level. Compare:

  <TMPL_WITH DEEP.PATH.TO.HASH>
  <TMPL_VAR NAME>: <TMPL_VAR AGE>
  </TMPL_WITH>

  <TMPL_VAR DEEP.PATH.TO.HASH.NAME>: <TMPL_VAR DEEP.PATH.TO.HASH.AGE>

Inside TMPL_WITH you can't reference parent nodes unless you're using global_vars.

=head2 TMPL_LOOP

The special name C<_> gives you the current paramater. In loops you can use it like this:

 <tmpl_loop foo>
  Current item: <tmpl_var _ >
 </tmpl_loop>

=head2 TMPL_LOOP_CONTEXT

With the directive

 <TMPL_LOOP_CONTEXT>

you can turn on loop_context_vars directly in the template. You usually would do that
directly after the loop tag (but you can do it anywhere in a loop):

 <tmpl_loop foo><tmpl_loop_context>
   <tmpl_var __counter__>
 </tmpl_loop foo>
 <tmpl_loop bar>
   <tmpl_if need_count>
     <tmpl_loop_context>
     <tmpl_var __counter__>
   </tmpl_if>
 </tmpl_loop bar>

If you only have a small number of loops that need the loop_context then this can
save you a bit of CPU, too. Set loop_context_vars to 0 and use the directive only.

=head2 TMPL_WHILE

Useful for iterating, for example over database resultsets.
The directive

  <tmpl_while resultset.fetchrow>
    <tmpl_var _.0>
  </tmpl_while>

will work like:
  while (my $row = $resultset->fetchrow) {
    print $row->[0];
  }

So the special variable name _ is set to the current item returned
by the iterator.

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

HTC will ignore anything between COMMENT directives.
This is useful for debugging, and also for documentation inside the
template which should not be outputted.

=head2 TMPL_NOPARSE

Anything between

  <tmpl_noparse>...</tmpl_noparse>

will not be recognized as template directives. Same syntax as TMPL_COMMENT.
It will output the content, though.

=head2 TMPL_VERBATIM

Anything between

  <tmpl_verbatim>...</tmpl_verbatim>

will not be recognized as template directives. But it will be HTML-Escaped. This
can be useful for debugging.
Same syntax as TMPL_COMMENT|NOPARSE.

=head2 TMPL_SWITCH

The SWITCH directive has the same syntax as VAR, IF etc.
The CASE directive takes a simple string or a comma separated list of strings.
Yes, without quotes. This will probably change!
With that directive you can do simple string comparisons.

 <tmpl_switch language>(or <tmpl_switch name=language>)
  <tmpl_case de>echt cool
  <tmpl_case en>very cool
  <tmpl_case es>superculo
  <tmpl_case fr,se>don't speak french or swedish
  <tmpl_case default>sorry, no translation for cool in language <%=language%> available
  <tmpl_case>(same as default)
 </tmpl_switch>

It's also possible to specify the default with a list of other strings:

 <tmpl_case fr,default>

Note that the default case should always be the last statement before the
closing switch.

=head2 OPTIONS

As you can cache the generated perl code in files, some of the options are fixed; that means
for example if you set the option case_sensitive to 0 and the next time you call the same template
with case_sensitive 1 then this will be ignored. The options below will be marked as (fixed).

=over 4

=item path

Path to template files

=item search_path_on_include

Search the list of paths specified with C<path> when including a template.
Default is 1 (different from HTML::Template).

=item cache_dir

Path to caching directory (you have to create it before)

=item cache

Is 1 by default. If set to 0, no memory cacheing is done. Only recommendable if
you have a dynamic template content (with scalarref, arrayre for example).

=item filename

Template to parse

=item scalarref

Reference to a scalar with your template content. It's possible to cache
scalarrefs, too, if you have Digest::MD5 installed. Note that your cache directory
might get filled with files from earlier versions. Clean the cache regularly.

Don't cache scalarrefs if you have dynamic strings. Your memory might get filled up fast!
Use the option

  cache => 0

to disable memory caching.

=item arrayref

Reference to array containing lines of the template content (newlines have
to be included)

=item filehandle

Filehandle which contains the template content. Note that HTC will not cache
templates created like this.

=item loop_context_vars (fixed)

Vars like C<__first__>, C<__last__>, C<__inner__>, C<__odd__>, C<__counter__>

To enable loop_context_vars is a slow down, too (about 10%). See L<"TMPL_LOOP_CONTEXT"> for
how to avoid this.

See L<"TMPL_LOOP_CONTEXT"> for special features.

=item global_vars (fixed)

If set to 1, every outer variable can be accessed from anywhere in the enclosing scope.

If set to 2, you don't have global vars, but have the possibility to go
up the stack one level. Example:

 <tmpl_var ...key>

This will get you up 2 levels (remember: one dot means root in HTC) and access the 'key'
element.

If set to 3 (C<3 == 1|2>) you have both, global vars and explicitly going up the stack.

So setting global_vars to 2 can save you from global vars but still allows you to
browse through the stack.

=item default_escape

  my $htc = HTML::Template::Compiled->new(
    ...
    default_escape => 'HTML', # or URI
  );

Now everything will be escaped for HTML unless you explicitly specify C<ESCAPE=0> (no escaping)
or C<ESCAPE=URI>.

=item deref (fixed)

Define the string you want to use for dereferencing, default is C<.> at the
moment:

 <TMPL_VAR hash.key>

=item method_call (fixed)

Define the string you want to use for method calls, default is . at
the moment:

 <TMPL_VAR object.method>

Don't use ->, though, like you could in earlier version. Var names can contain:
Numbers, letters, '.', '/', '+', '-' and '_'. (Just like HTML::Template)
 
=item default_path (fixed)

  my $htc = HTML::Template::Compiled->new(
    ...
    default_path
         # default is PATH_DEREF
      => HTML::Template::Compiled::Utils::PATH_FORMATTER,
  );

Is needed if you have an unqualified tmpl_var that should be resolved as
a call to your formatter, for example. Otherwise you have to call it
fully qualified. If your formatter_path is '/', you'd say tmpl_var C<_/method>.
With the option default_path you can make that the default, so you don't need
the C<_/>: C<tmpl_var method>. If you don't use formatters, don't care about
this option.

=item line_numbers

NOTE: This option does not exist any more; line numbers will alway be reported.

For debugging: prints the line number of the wrong tag, e.g. if you have
a /TMPL_IF that does not have an opening tag.

=item case_sensitive (fixed)

default is 1, set it to 0 to use this feature like in HTML::Template. Note that
this can slow down your program a lot (50%).

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

=item out_fh (fixed)

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

=item tagstyle (fixed)

Specify which styles you want to use. This option takes an arrayref
with strings of named tagstyles or your own regexes.

At the moment there are the following named tagstyles builtin:

    # classic (active by default)
    <TMPL_IF foo><tmpl_var bar></TMPL_IF>
    # comment (active by default)
    <!-- TMPL_IF foo --><!-- TMPL_VAR bar --><!-- /TMPL_IF -->
    # asp (active by default)
    <%if foo%><%VAR bar%><%/if%>
    # php (not active by default)
    <?if foo?><?var bar?><?/if foo?>
    # tt (not active by default)
    [%if foo%][%var bar%][%/if foo%]

You deactive a style by saying -stylename. You activate by saying
+stylename.

Define your own tagstyle by specifying for regexes. For example
you want to use {C<{if foo}}{{var bar}}{{/if foo}}>, then your
definition should be:

    [
        qr({{), start of opening tag
        qr(}}), # end of opening tag
        qr({{/), # start of closing tag
        qr(}}), # end of closing tag
    ]

NOTE: do not specify capturing parentheses in you regexes. If you
need parentheses, use C<(?:foo|bar)> instead of C<(foo|bar)>.

Say you want to deactivate asp-style, comment-style, activate php- and
tt-style and your own C<{{}} > style, then say:

    my $htc = HTML::Template::Compiled->new(
        ...
        tagstyle => [
            qw(-asp -comment +php +tt),
            [ qr({{), qr(}}), qr({{/), qr(}})],
        ],
    );


=item formatter

With formatter you can specify how an object should be rendered. This is useful
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

=item formatter_path (fixed)

see formatter. Defaults to '/'

=item debug

If set to 1 you will get the generated perl code on standard error

=item use_query

Specify if you plan to use the query() method. Default is 0.

Explanation: If you want to use query() to collect information
on the template HTC has to do extra-work while compiling and
uses extra-memory, so you can choose to save HTC work by
setting use_query to 0 (default) or letting HTC do the extra
work by setting it to 1. If you would like 1 to be the default,
write me. If enough people write me, I'll think abou it =)

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

=item param

Works like in L<HTML::Template>.

=item query

Works like in L<HTML::Template>. But it is not activated by default. If you want
to use it, specify the use_query option.

=item preload

Class method. Will preload all template files from a given cachedir into memory. Should
be done, for example in a mod_perl environment, at server startup, so all templates
go into "shared memory"

  HTML::Template::Compiled->preload($cache_dir);

If you don't do preloading in mod_perl, memory usage might go up if you have a lot
of templates.

=item precompile

Class method. It will precompile a list of template files into the specified
cache directory. See L<"PRECOMPILE">.

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

You can set the expire time of a template by
  HTML::Template::Compiled->ExpireTime($seconds);
(C<$HTML::Template::Compiled::NEW_CHECK> is deprecated).
So
  HTML::Template::Compiled->ExpireTime(60 * 10);
will check after 10 minutes if the tmpl file was modified. Set it to a
very high value will then ignore any changes, until you delete the
generated code.

=head1 TODO

fix C<path> option, associate, methods with simple parameters,
expressions, lazy-loading, pluggable, ...

=head2 SECURITY

HTML::Template::Compiled uses basically the same file caching model as, for example, Template-
Toolkit does: The compiled Perl code is written to disk and later reread via C<do> or
by reading the file and C<eval> the content.

If you are sharing a read/write environment with untrusted users (for example on
a machine with a webserver, like many webhosters offer, and all scripts are running
as the same httpd user), realize that there is possibility of modifying the Perl code that is
cached and then executed. The best solution is to not be in such an
environment!

In this case it is the safest option to generate your compiled templates on a local machine
and just put the compiled templates onto the server, with no write access for the http server.
Set the C<ExpireTime> variable to a high value so that HTC never attempts to check the
template timestamp to force a regenerating of the code.

If you are alone on the machine, but you are running under taint mode (see L<perlsec>) then
you have to explicitly set the C<$UNTAINT> variable to 1. HTC will then untaint the code for you
and treat it as if it were safe (it hopefully is =).

=head2 PRECOMPILE

I think there is no way to provide an easy function for precompiling,
because every template can have different options.
If you have all your templates with the same options, then you can use the
precompile class method.
It works like this:

  HTML::Template::Compiled->precompile(
    # usual options like path, default_escape, global_vars, cache_dir, ...
    filenames => [ list of template-filenames ],
  );

This will then pre-compile all templates into cache_dir. Now you would just put this
directory onto the server, and it doesn't need any write-permissions, as it
will be never changed (until you update it because templates have changed).

=head1 BENCHMARKS

The options C<case_sensitive>, C<loop_context_vars> and C<global_vars> can have the biggest influence
on speed.

Setting case_sensitive to 1, loop_context_vars to 0 and global_vars to 0 saves time.

On the other hand, compared to HTML::Template, the speed gain is biggest (under mod_perl
you save ca. 86%, under CGI about 10%), if you use case_sensitive = 1, loop_context_vars = 0,
global_vars = 1.

=head1 BUGS

Probably many bugs I don't know yet =)

Use the bugtracking system to report a bug:
http://rt.cpan.org/NoAuth/Bugs.html?Dist=HTML-Template-Compiled

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

Co-Author Mark Stosberg

=head1 CREDITS

Sam Tregar big thanks for ideas and letting me use his L<HTML::Template> test suite

Bjoern Kriews for original idea and contributions

Ronnie Neumann, Martin Fabiani, Kai Sengpiel, Sascha Kiefer, Jan Willamowius for ideas and beta-testing

perlmonks.org and perl-community.de for everyday learning

Corion, Limbic~Region, tye, runrig and others from perlmonks.org 

=head1 COPYRIGHT AND LICENSE

Copyright (C) 2005 by Tina Mueller

This library is free software; you can redistribute it and/or modify
it under the same terms as Perl itself, either Perl version 5.8.3 or,
at your option, any later version of Perl 5 you may have available.


=cut
