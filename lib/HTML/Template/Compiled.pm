package HTML::Template::Compiled;
# $Id: Compiled.pm 1128 2011-10-31 19:59:56Z tinita $
# doesn't work with make tardist
#our $VERSION = ($version_pod =~ m/^\$VERSION = "(\d+(?:\.\d+)+)"/m) ? $1 : "0.01";
our $VERSION = "0.95_002";
use Data::Dumper;
BEGIN {
use constant D => $ENV{HTC_DEBUG} || 0;
}
use strict;
use warnings;
use Digest::MD5 qw/ md5_hex /;

our $Storable = 1;
use Carp;
use Fcntl qw(:seek :flock);
use File::Spec;
use File::Basename qw(dirname basename);
use HTML::Template::Compiled::Utils qw(:walkpath :log :escape &md5);
use HTML::Template::Compiled::Expression qw(:expressions);
use HTML::Template::Compiled::Compiler;
# TODO
eval {
    require URI::Escape;
};
eval {
    require Encode;
};
my $Encode = $@ ? 0 : 1;

use base 'Exporter';
our @EXPORT_OK = qw(&HTC);
use HTML::Template::Compiled::Parser qw(
    $CASE_SENSITIVE_DEFAULT $NEW_CHECK
    $DEBUG_DEFAULT $SEARCHPATH
    %FILESTACK %COMPILE_STACK %PATHS $DEFAULT_ESCAPE $DEFAULT_QUERY
    $UNTAINT $DEFAULT_TAGSTYLE $MAX_RECURSE
);
use vars qw($__ix__);

use constant MTIME    => 0;
use constant CHECKED  => 1;
use constant LMTIME   => 2;
use constant LCHECKED => 3;

our $DEBUG = 0;
our $LAST_EXCEPTION;

# options / object attributes
use constant PARAM => 0;

BEGIN {
    my @map = (
        undef, qw(
          path md5_path filename file scalar filehandle
          file_cache cache_dir cache search_path
          loop_context case_sensitive global_vars
          default_path
          debug debug_file objects perl out_fh default_escape
          filter formatter
          globalstack use_query parse_tree parser compiler includes
          plugins open_mode
        )
          #use_expressions
    );

    for my $i ( 1 .. $#map ) {
        my $method = "_$map[$i]";
        my $get    = eval qq#sub { return \$_[0]->[$i] }#;
        my $set;
            $set = eval qq#sub { \$_[0]->[$i] = \$_[1] }#;
        no strict 'refs';
        *{"get$method"} = $get;
        *{"set$method"} = $set;
    }
}

# tired of typing?
sub HTC { __PACKAGE__->new(@_) }

sub new {
    my ( $class, %args ) = @_;
    D && $class->log("new()");
    # handle the "type", "source" parameter format (does anyone use it?)
    if ( exists $args{type} ) {
        exists $args{source} or $class->_error_no_source();
        $args{type} =~ m/^(?:filename|scalarref|arrayref|filehandle)$/
          or $class->_error_wrong_source();
        $args{ $args{type} } = $args{source};
        delete $args{type};
        delete $args{source};
    }
    if (exists $args{filename}) {
        return $class->new_file($args{filename}, %args);
    }
    elsif (exists $args{scalarref}) {
        return $class->new_scalar_ref($args{scalarref}, %args);
    }
    elsif (exists $args{filehandle}) {
        return $class->new_filehandle($args{filehandle}, %args);
    }
    elsif (exists $args{arrayref}) {
        return $class->new_array_ref($args{arrayref}, %args);
    }
    croak("$class->new called with not enough arguments");
}

sub _error_no_query {
    my ($self) = @_;
    my $class = ref $self || $self;
    carp "You are using query() but have not specified that you want to use it"
    . " (specify with use_query => 1)";
}

sub _error_not_compiled {
    my ($self) = @_;
    my $class = ref $self || $self;
    carp "Template was not compiled yet";
}

sub _error_wrong_source {
    my ($self) = @_;
    my $class = ref $self || $self;
    croak("$class->new() : type parameter must be set to 'filename', "
        . "'arrayref', 'scalarref' or 'filehandle'!");
}

sub _error_no_source {
    my ($self) = @_;
    my $class = ref $self || $self;
    croak("$class->new() called with 'type' parameter set,"
       . " but no 'source'!");
}

sub _error_template_sources {
    my ($self) = @_;
    my $class = ref $self || $self;
    croak(
        "$class->new called with multiple (or no) template sources specified!"
          . "A valid call to new() has exactly ne filename => 'file' OR exactly one"
          . " scalarref => \\\$scalar OR exactly one arrayref => \\\@array OR"
          . " exactly one filehandle => \*FH"
      );
}

sub _error_empty_filename {
    my ($self) = @_;
    my $class = ref $self || $self;
    croak("$class->new called with empty filename parameter!");
}

sub new_from_perl {
    my ($class, %args) = @_;
    my $self = bless [], $class;
    D && $self->log("new(perl) filename: $args{filename}");

    $self->init_cache(\%args);
    $self->init(%args);
    $self->set_perl( $args{perl} );
    $self->set_cache( exists $args{cache} ? $args{cache} : 1 );
    $self->set_filename( $args{filename} );
    $self->set_cache_dir( $args{cache_dir} );
    my $md5path = md5_hex(@{ $args{path} || [] });
    $self->set_path( $args{path} );
    $self->set_md5_path( $md5path );
    $self->set_scalar( $args{scalarref} );

    unless ( $self->get_scalar ) {
        my $file =
          $self->createFilename( $self->get_path, $self->get_filename );
        $self->set_file($file);
    }
    return $self;
}

sub new_file {
    my ($class, $filename, %args) = @_;
    my $self = bless [], $class;
    $self->_check_deprecated_args(%args);
    $args{path} = $self->build_path($args{path});
    $self->_error_empty_filename()
        if (!defined $filename or !length $filename);
    $args{filename} = $filename;
    if (exists $args{scalarref}
        || exists $args{arrayref} || exists $args{filehandle}) {
        $self->_error_template_sources;
    }
    $self->set_filename( $filename );
    $self->set_cache( exists $args{cache} ? $args{cache} : 1 );
    $self->init_cache(\%args);
    #$self->set_cache_dir( $args{cache_dir} );
    my $md5path = md5_hex(@{ $args{path} || [] });
    my $test = $args{path};
    $self->set_path( $args{path} );
    $self->set_md5_path( $md5path );
    if (my $t = $self->from_cache(\%args)) {
        $t->init_includes();
        return $t;
    }
    $self->init(%args);
    $self->from_scratch;
    $self->init_includes;
    return $self;
}

sub new_filehandle {
    my ($class, $filehandle, %args) = @_;
    my $self = bless [], $class;
    $self->_check_deprecated_args(%args);
    if (exists $args{scalarref}
        || exists $args{arrayref} || exists $args{filename}) {
        $self->_error_template_sources;
    }
    $args{filehandle} = $filehandle;
    $args{path} = $self->build_path($args{path});
    $self->set_filehandle( $args{filehandle} );
    $self->set_cache(0);
    $self->init_cache(\%args);
    #$self->set_cache_dir( $args{cache_dir} );
    my $md5path = md5_hex(@{ $args{path} || [] });
    $self->set_path( $args{path} );
    $self->set_md5_path( $md5path );
    if (my $t = $self->from_cache(\%args)) {
        return $t;
    }
    $self->init(%args);
    $self->from_scratch;
    $self->init_includes;
    return $self;
}

sub new_array_ref {
    my ($class, $arrayref, %args) = @_;
    if (exists $args{scalarref}
        || exists $args{filehandle} || exists $args{filename}) {
        $class->_error_template_sources;
    }
    my $scalarref = \( join '', @$arrayref );
    delete $args{arrayref};
    return $class->new_scalar_ref($scalarref, %args);
}

sub new_scalar_ref {
    my ($class, $scalarref, %args) = @_;
    my $self = bless [], $class;
    $self->_check_deprecated_args(%args);
    if (exists $args{arrayref}
        || exists $args{filehandle} || exists $args{filename}) {
        $self->_error_template_sources;
    }
    $args{scalarref} = $scalarref;
    $args{path} = $self->build_path($args{path});
    $self->set_cache( exists $args{cache} ? $args{cache} : 1 );
    $self->init_cache(\%args);
    #$self->set_cache_dir( $args{cache_dir} );
    $self->set_scalar( $args{scalarref} );
    my $text = $self->get_scalar;
    my $md5  = md5($$text);
    if ($args{cache} and !$md5) {
        croak "For caching scalarrefs you need Digest::MD5";
    }
    $self->set_filename($md5);
    D && $self->log("md5: $md5");
    my $md5path = md5_hex(@{ $args{path} || [] });
    $self->set_path( $args{path} );
    $self->set_md5_path( $md5path );
    if (my $t = $self->from_cache(\%args)) {
        return $t;
    }
    $self->init(%args);
    $self->from_scratch;
    $self->init_includes;
    return $self;
}

sub init_includes {
    my ($self) = @_;
    my $includes = $self->get_includes;
    my $cache = $self->get_cache_dir||'';
    for my $fullpath (keys %$includes) {
        my ($path, $filename, $htc) = @{ $includes->{$fullpath} };
        D && $self->log("checking $fullpath ($filename) $htc?");
        $cache .= '-' . $self->get_md5_path;
        if (HTML::Template::Compiled::needs_new_check(
                $cache||'',$filename)
        ) {
            $htc = $self->new_from_object($path,$filename,$fullpath,$cache);
        }
        $includes->{$fullpath}->[2] = $htc;
        $includes->{$fullpath}->[2]->set_plugins($self->get_plugins);
    }
}

sub build_path {
    my ($self, $path) = @_;
    unless (defined $path) {
        $path = [];
    }
    elsif (!ref $path) {
        $path = [$path];
    }
    defined $ENV{'HTML_TEMPLATE_ROOT'}
        and push @$path, $ENV{'HTML_TEMPLATE_ROOT'};
    return $path;
}


sub init_runtime_args {
    my ($self, %args) = @_;
    D && $self->log("init_runtime_args()");
    if ( my $filter = $args{filter} ) {
        unless ( $self->get_filter ) {
            $self->set_filter($filter);
        }
    }
    return $self;
}

sub from_scratch {
    my ($self) = @_;
    D && $self->log("from_scratch filename=".$self->get_filename);
    my $fname = $self->get_filename;
    if ( defined $fname and !$self->get_scalar and !$self->get_filehandle ) {

        #D && $self->log("tried from_cache() filename=".$fname);
        my $file = $self->createFilename( $self->get_path, $fname );
        D && $self->log("set_file $file ($fname)");
        $self->set_file($file);
    }
    elsif ( defined $fname ) {
        $self->set_file($fname);
    }
    D && $self->log( "compiling... " . $self->get_filename );
    $self->compile();
    return $self;
}

sub from_cache {
    my ($self, $args) = @_;
    my $t;
    D && $self->log( "from_cache() filename=" . $self->get_filename );

    $args ||= {};
    my $plug = $args->{plugin} || [];
    # try to get memory cache
    if ( $self->get_cache ) {
        my $dir = $self->get_cache_dir;
        $dir = '' unless defined $dir;
        $dir .= '-' . $self->get_md5_path;
        my $fname  = $self->get_filename;
        $t = $self->from_mem_cache($dir,$fname);
        if ($t) {
            $t->set_plugins($plug) if @$plug;
            return $t;
        }
    }
    D && $self->log( "from_cache() 2 filename=" . $self->get_filename );

    # not in memory cache, try file cache
    if ( $self->get_cache_dir ) {
        #$self->init_runtime_args(%args);
        my $file = $self->get_scalar || $self->get_filehandle
            ? $self->get_filename
            : $self->createFilename( $self->get_path, $self->get_filename );
        my $dir     = $self->get_cache_dir;
        $t = $self->from_file_cache($dir, $file);
        if ($t) {
            $t->set_plugins($plug) if @$plug;
            return $t;
        }
    }
    D && $self->log( "from_cache() 3 filename=" . $self->get_filename );
    return;
}

{
    my $cache;
    # {
    #   $cachedir => {
    #     $filename => $htc_object,
    my $times;

    sub needs_new_check {
        my ($dir, $fname) = @_;
        my $times  = $times->{$dir}->{$fname} or return 1;
        my $now = time;
        return 0 if $now - $times->{checked} < $NEW_CHECK;
        return 1;
    }

    sub from_mem_cache {
        my ($self, $dir, $fname) = @_;
        my $cached = $cache->{$dir}->{$fname};
        my $times  = $times->{$dir}->{$fname};
        D && $self->log("\$cached=$cached \$times=$times \$fname=$fname\n");
        if ( $cached && $self->uptodate($times) ) {
            return $cached->clone;
        }
        D && $self->log("no or old memcache");
        return;
    }

    sub _debug_cache {
        my ($self) = @_;
        my $dir = $self->get_cache_dir;
        my $objects = $cache->{$dir};
        my $times = $times->{$dir};
        warn Data::Dumper->Dump([\$times], ['times']);
        my @keys = keys %$objects;
        warn Data::Dumper->Dump([\@keys], ['keys']);
    }
    sub add_mem_cache {
        my ( $self, %times ) = @_;
        D && $self->stack(1);
        my $dir = $self->get_cache_dir;
        $dir = '' unless defined $dir;
        my @c = caller();
        $dir .= '-' . $self->get_md5_path;
        my $fname = $self->get_filename;
        D && $self->log( "add_mem_cache $fname" );
        my $clone = $self->clone;
        $clone->clear_params();
        my @plugs = @{ $self->get_plugins || [] };
        for my $i (0 .. $#plugs) {
            if (ref $plugs[$i]) {
                if ($plugs[$i]->can('serialize')) {
                    $plugs[$i] = $plugs[$i]->serialize();
                }
            }
        }
        $clone->set_plugins(\@plugs);
        $cache->{$dir}->{$fname} = $clone;
        $times->{$dir}->{$fname} = \%times;
    }

    sub clear_cache {
        my $dir = $_[0]->get_cache_dir;

        # clear the whole cache
        $cache = {}, $times = {}, return unless defined $dir;

        # only specific directory
        $cache->{$dir} = {};
        $times->{$dir} = {};
    }

    sub clear_filecache {
        my ( $self, $dir ) = @_;
        defined $dir
          or $dir = $self->get_cache_dir;
        return unless -d $dir;
        ref $self and $self->lock;
        opendir my $dh, $dir or die "Could not open '$dir': $!";
        my @files = grep { m/(\.pl|\.storable)$/ } readdir $dh;
        for my $file (@files) {
            my $file = File::Spec->catfile( $dir, $file );
            unlink $file or die "Could not delete '$file': $!";
        }
        ref $self and $self->unlock;
        return 1;
    }

    sub uptodate {
        my ( $self, $cached_times ) = @_;
        return 1 if $self->get_scalar;
#         unless ($cached_times) {
#             my $dir = $self->get_cache_dir;
#             $dir = '' unless defined $dir;
#             my $fname  = $self->get_filename;
#             my $cached = $cache->{$dir}->{$fname};
#             $cached_times  = $times->{$dir}->{$fname};
#             return unless $cached;
#         }
        my $now = time;
        if ( $now - $cached_times->{checked} < $NEW_CHECK ) {
            return 1;
        }
        else {
            my $file = $self->createFilename( $self->get_path, $self->get_filename );
            $self->set_file($file);
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
    my $compiler = $self->get_compiler;
    if ( my $file = $self->get_file and !$self->get_scalar ) {

        D && $self->log( "compile from file " . $file );
        die "Could not open '$file': $!" unless -f $file;
        my @times = $self->_checktimes($file);
        my $text  = $self->_readfile($file);
        my ( $source, $compiled ) = $compiler->compile( $self, $text, $file );
        $self->set_perl($compiled);
        $self->get_cache and $self->add_mem_cache(
            checked => time,
            mtime   => $times[MTIME],
        );
        D && $self->log("compiled $file");

        if ( $self->get_cache_dir ) {
            D && $self->log("add_file_cache($file)");
            $self->add_file_cache(
                $source,
                checked => time,
                mtime   => $times[MTIME],
            );
        }
    }
    elsif ( my $text = $self->get_scalar ) {
        my $md5 = $self->get_filename;    # yeah, weird
        D && $self->log("compiled $md5");
        my ( $source, $compiled ) = $compiler->compile( $self, $$text, $md5 );
        $self->set_perl($compiled);
        if ( $self->get_cache_dir ) {
            D && $self->log("add_file_cache($file)");
            $self->add_file_cache(
                $source,
                checked => time,
                mtime   => time,
            );
        }
    }
    elsif ( my $fh = $self->get_filehandle ) {
        local $/;
        my $data = <$fh>;
        my ( $source, $compiled ) = $compiler->compile( $self, $data, '' );
        $self->set_perl($compiled);

    }
}

sub add_file_cache {
    my ( $self, $source, %times ) = @_;
    $self->lock;
    my $cache    = $self->get_cache_dir;
    my $plfile   = $self->escape_filename( $self->get_file );
    my $filename = $self->get_filename;
    my $lmtime   = localtime $times{mtime};
    my $lchecked = localtime $times{checked};
    my $cachefile = "$cache/$plfile";
    D && $self->log("add_file_cache() $cachefile");
    if ($Storable and require_storable()) {
        #require Storable;
        local $Storable::Deparse = 1;
        my $clone = $self->clone;
        $clone->prepare_for_cache;
        my $v = $self->VERSION || '0.01';
        my $to_cache = {
            htc => $clone,
            version => $v,
            times => {
                mtime => $times{mtime},
                checked => $times{checked},
            },
        };
        # TODO Storable cannot store qr//
        # but as we don't need those serialized anyway
        # we let Storable just store a dummy entry
        local $Storable::forgive_me = 1;
        local $SIG{__WARN__} = sub {
            my ($w) = @_;
            unless ($w =~ m/Can't store item REGEXP/) {
                warn $w;
            }
        };
        Storable::store($to_cache, "$cachefile.storable");
    }
    else {
    my $utf8 = $Encode && Encode::is_utf8($source);
    my $use_utf8 = $utf8 ? 'use utf8;' : '';
    open my $fh, ">" . ($utf8 ? ':utf8' : ''), "$cachefile.pl" or die $!;    # TODO File::Spec
    my $path     = $self->get_path;
    my $path_str = '['
      . ( join ', ', map { $self->quote_file($_) } @$path )
      . ']';
    my $isScalar = $self->get_scalar ? 1 : 0;
    my $query_info = $self->get_parse_tree;
    $query_info = Data::Dumper->Dump([$query_info], ['query_info']);
    my $parser =$self->get_parser;
    $parser = Data::Dumper->Dump([\$parser], ['parser']);
    local $Data::Dumper::Deepcopy = 1;
    my $includes = $self->get_includes;
    my $includes_empty = {map {
            $_ => [$includes->{$_}->[0], $includes->{$_}->[1], 0],
        } keys %$includes};
    my $includes_to_string = Data::Dumper->Dump(
        [$includes_empty], ['includes']
    );
    #$includes_to_string =~ s/\$includes = //;
    my $search_path = $self->get_search_path || 0;
    my $gl = $self->get_global_vars;
    my $debug_file = $self->get_debug_file;
    $debug_file =~ tr/a-z0,//cd;
    my $use_objects = $self->get_objects;
    $use_objects =~ tr/a-z0//cd;
    my $plugins = $self->get_plugins;
    my $plugin_dump = Data::Dumper->Dump([\@$plugins], ['plugin_dump']);
    my $file_args = $isScalar
      ? <<"EOM"
        scalarref => $isScalar,
        filename => '@{[$self->get_filename]}',
EOM
      : <<"EOM";
        filename => '@{[$self->get_filename]}',
EOM
    my $package = <<"EOM";
    $use_utf8
    package HTML::Template::Compiled;
# file date $lmtime
# last checked date $lchecked
# @$plugins
my $plugin_dump;
my $query_info;
my \$parser;
$parser;
my $includes_to_string;
my \$args = {
    # HTC version
    class => '@{[ref $self]}',
    version => '$VERSION',
    times => {
        mtime => $times{mtime},
        checked => $times{checked},
    },
    htc => {
        case_sensitive => @{[$self->get_case_sensitive]},
        cache_dir => '$cache',
        cache => '@{[$self->get_cache]}',
$file_args
    path => $path_str,
    out_fh => @{[$self->get_out_fh]},
    default_path   => '@{[$self->get_default_path]}',
    default_escape => '@{[$self->get_default_escape]}',
    loop_context_vars => '@{[$self->get_loop_context||0]}',
    use_query => \$query_info,
    parser => \$parser,
    global_vars => $gl,
    debug_file => '$debug_file',
    objects => '$use_objects',
    includes => \$includes,
    search_path_on_include => $search_path,
    plugin => \$plugin_dump,
    # TODO
    # dumper => ...
    # template subroutine
    perl => $source,
    },
};
EOM
    print $fh $package;
    D && $self->log("$cache/$plfile.pl generated");
    }
    $self->unlock;
}

sub get_plugin {
    my ($self, $class) = @_;
    for my $plug (@{ $self->get_plugins || [] }) {
        return $plug if (ref $plug || $plug) eq $class;
    }
    return;
}

sub from_file_cache {
    my ($self, $dir, $file) = @_;
    D && $self->stack;
    D && $self->log("include file: $file");

    my $escaped = $self->escape_filename($file);
    my $req     = File::Spec->catfile( $dir, "$escaped.".($Storable && require_storable()?"storable":"pl") );
    return unless -f $req;
    return $self->include_file($req);
}

sub include_file {
    my ( $self, $req ) = @_;
    D && $self->log("do $req");
    my $r;
    my $t;
    if ($Storable && require_storable()) {
        #require Storable;
        local $Storable::Eval = 1;
        my $cache;
        eval {
            $cache = Storable::retrieve($req);
        };
        #warn __PACKAGE__.':'.__LINE__.": error? $@\n";
        return if $@;
        my $cached_version = $cache->{version};
        $t = $cache->{htc};
        if (($t->VERSION || '0.01') ne $cached_version || !$t->uptodate( $cache->{times} )) {
            # is not uptodate
            return;
        }
        my $plug = $t->get_plugins || [];
        $t->get_cache and $t->add_mem_cache(
            checked => $cache->{times}->{checked},
            mtime   => $cache->{times}->{mtime},
        );
        $t->init_plugins($plug);
    }
    else {
    if ($UNTAINT) {
        # you said explicitly that you can trust your compiled code
        open my $fh, '<:utf8', $req or die "Could not open '$req': $!";
        my $code = <$fh>;
        if ($code =~ m/use utf8/) {
            binmode $fh, ':utf8';
            $Encode and Encode::_utf8_on($code);
        }
        local $/;
        $code .= <$fh>;
        my $utf8 = $Encode && Encode::is_utf8($code);
        if ( $code =~ m/(\A.*\z)/ms ) {
            $code = $1;
        }
        else {
            $code = "";
        }
        if ($utf8) {
            Encode::_utf8_on($code);
        }
        $r = eval $code;
    }
    else {
        $r = do $req;
    }
    if ($@) {
        # we had an error while including
        die "Error while including '$req': $@";
    }
    my $cached_version = $r->{version};
    my $class = $r->{class} || 'HTML::Template::Compiled';
    my $args = $r->{htc};
    # we first just create from cached perl-code
    $t = $class->new_from_perl(%$args);
    if ($VERSION ne $cached_version || !$t->uptodate( $r->{times} )) {
        # is not uptodate
        return;
    }
    $t->set_includes( $args->{includes} );
    $t->init_includes;
    $t->get_cache and $t->add_mem_cache(
        checked => $r->{times}->{checked},
        mtime   => $r->{times}->{mtime},
    );
    }
    return $t;
}

sub createFilename {
    my ( $self, $path, $filename ) = @_;
    D && $self->log("createFilename($path,$filename)");
    D && $self->stack(1);
    if ($path) {
        local $" = "\\";
        my $cached = $PATHS{"@$path"}->{$filename};
        return $cached if defined $cached;
    }
    if ( !$path or
        (File::Spec->file_name_is_absolute($filename) &&
        -f $filename) ) {
        return $filename;
    }
    else {
        D && $self->log( "file: " . File::Spec->catfile( $path, $filename ) );
        if ($path && @$path) {
            for ( @$path ) {
                #if (ref $_) {
                #    my $foo = basename $$_;
                #    my ($dir, $f) = (dirname($$_), basename($$_));
                #    my $found = 0;
                #    while (defined $f) {
                #        ($dir, $f) = (dirname($dir), basename($dir));
                #        #sleep 1;
                #        my $fp = File::Spec->catfile( $dir, $filename );
                #        #warn __PACKAGE__.':'.__LINE__.": fp=$fp\n";
                #        if (-f $fp) {
                #            local $" = "\\";
                #            $PATHS{"@$path"}->{$filename} = $fp;
                #            return $fp;
                #        }
                #        last if $dir eq '.';
                #    }
                #}
                my $fp = File::Spec->catfile( $_, $filename );
                if (-f $fp) {
                    local $" = "\\";
                    $PATHS{"@$path"}->{$filename} = $fp;
                    return $fp;
                }
            }
        }
        elsif (-f $filename) {
            $PATHS{''}->{$filename} = $filename;
            return $filename;
        }

        # TODO - bug with scalarref
        croak "'$filename' not found";
    }
}

sub dump {
    my ( $self, $var ) = @_;
    require Data::Dumper;
    local $Data::Dumper::Indent   = 1;
    local $Data::Dumper::Sortkeys = 1;
    return Data::Dumper->Dump( [$var], ['DUMP'] );
}

sub _check_deprecated_args {
    my ($self, %args) = @_;
    for (qw(method_call deref formatter_path)) {
        if (exists $args{$_}) {
            croak "Option $_ is deprecated";
        }
    }
    if (exists $args{dumper}) {
        croak "Option dumper is deprecated, use a plugin instead";
    }
    if (exists $args{formatter}) {
        croak "Option formatter is deprecated, see documentation";
    }
}

sub init_cache {
    my ($self, $args) = @_;
    if (exists $args->{cache_dir}) {
        # will soon be deprecated
        $args->{file_cache_dir} = $args->{cache_dir};
        unless (exists $args->{file_cache}) {
            # warn in future versions
            $args->{file_cache} = 1;
        }
    }
    $self->set_cache_dir($args->{file_cache_dir}) if $args->{file_cache};
    my $cachedir = $self->get_cache_dir;
    if ($args->{file_cache} and defined $cachedir and not -d $cachedir) {
        croak "Cachedir '$cachedir' does not exist";
    }
}

sub init {
    my ( $self, %args ) = @_;
    my %defaults = (

        # defaults
        search_path_on_include => $SEARCHPATH,
        loop_context_vars      => 0,
        case_sensitive         => $CASE_SENSITIVE_DEFAULT,
        debug                  => $DEBUG_DEFAULT,
        debug_file             => 0,
        objects                => 'strict',
        out_fh                 => 0,
        global_vars            => 0,
        default_escape         => $DEFAULT_ESCAPE,
        default_path           => PATH_DEREF,
        use_query              => $DEFAULT_QUERY,
        #use_expressions        => 0,
        use_perl               => 0,
        open_mode              => '',
        no_includes            => 0,
        %args,
    );
    $self->set_loop_context(1) if $args{loop_context_vars};
    $self->set_case_sensitive( $defaults{case_sensitive} );
    $self->set_default_escape( $defaults{default_escape} );
    $self->set_default_path( $defaults{default_path} );
    $self->set_use_query( $defaults{use_query} );
    #$self->set_use_expressions( $defaults{use_expressions} );
    if ($defaults{use_expressions}) {
        require HTML::Template::Compiled::Expr;
    }
    if ($defaults{open_mode}) {
        $defaults{open_mode} =~ s/^[<>]//; # <:utf8
    }
    $self->set_open_mode( $defaults{open_mode} );
    $self->set_search_path( $defaults{search_path_on_include} );
    $self->set_includes({});
    if ( $args{filter} ) {
        require HTML::Template::Compiled::Filter;
        $self->set_filter(
            HTML::Template::Compiled::Filter->new( $args{filter} ) );
    }
    $self->set_debug( $defaults{debug} );
    $self->set_debug_file( $defaults{debug_file} );
    $self->set_objects( $defaults{objects} );
    if ($defaults{objects} and $defaults{objects} eq 'nostrict') {
        require Scalar::Util;
    }
    $self->set_out_fh( $defaults{out_fh} );
    $self->set_global_vars( $defaults{global_vars} );
    my $tagstyle = $args{tagstyle};
    my $parser;
    if (ref $tagstyle eq 'ARRAY') {
        # user specified named styles or regexes
        $parser = $self->parser_class->new(
            tagstyle => $tagstyle,
            use_expressions => $defaults{use_expressions},
        );
        $parser->set_perl($defaults{use_perl});
    }
    $args{parser} = ${$args{parser}} if ref $args{parser} eq 'REF';
    if (UNIVERSAL::isa($args{parser}, 'HTML::Template::Compiled::Parser')) {
        $parser = $args{parser};
    }
    unless ($parser) {
        $parser ||= $self->parser_class->default();
        $parser->set_perl($defaults{use_perl});
        $parser->set_expressions($defaults{use_expressions});
    }
    if ($defaults{use_perl}) {
        $parser->add_tagnames({
            HTML::Template::Compiled::Token::OPENING_TAG() => {
                PERL => [sub { 1 }],
            }
        });
    }
    if ($defaults{no_includes}) {
        $parser->remove_tags(qw/ INCLUDE INCLUDE_VAR INCLUDE_STRING /);
    }
    $self->set_parser($parser);
    my $compiler = $self->compiler_class->new;
    $self->set_compiler($compiler);
    if ($defaults{plugin}) {
        my $plugins = ref $defaults{plugin} eq 'ARRAY' ? $defaults{plugin} : [$defaults{plugin}];
        $self->init_plugins($plugins);
        $self->set_plugins($plugins);
    }
}

sub init_plugins {
    my ($self, $plugins) = @_;
    my $parser = $self->get_parser;
    my $compiler = $self->get_compiler;
    for my $plug (@$plugins) {
        if (ref $plug) {
        }
        elsif ($plug =~ m/^::/) {
            $plug = "HTML::Template::Compiled::Plugin$plug";
        }
        unless ($plug->can('register')) {
            eval "require $plug";
            if ($@) {
                carp "Could not load plugin $plug\n";
            }
        }
        my $actions = $self->get_plugin_actions($plug);
        if (my $tagnames = $actions->{tagnames}) {
            $parser->add_tagnames($tagnames);
        }
        if (my $escape = $actions->{escape}) {
            $compiler->add_escapes($escape);
        }
        if (my $tags = $actions->{compile}) {
            $compiler->add_tags($tags);
        }
    }
}

{
    my $classes = {};

    sub register {
        my ($class, $plugins) = @_;
        $plugins = [$plugins] unless ref $plugins eq 'ARRAY';
        for my $plug (@$plugins) {
            my $actions = $plug->register;
            $classes->{ref $plug || $plug} = $actions;
        }
    }

    sub get_plugin_actions {
        my ($self, $pclass) = @_;
        return $classes->{ref $pclass || $pclass};
    }
}
    

sub _readfile {
    my ( $self, $file ) = @_;
    my $open_mode = $self->get_open_mode;
    my $fh;
    if ($] < 5.007001) {
        open $fh, $file or die "Cannot open '$file': $!";
    }
    else {
        $open_mode = '' unless length $open_mode;
        open $fh, "<$open_mode", $file or die "Cannot open '$file': $!";
    }
    local $/;
    my $text = <$fh>;
    return $text;
}

sub get_code {
    my ($self) = @_;
    my $perl = $self->get_perl;
    return $perl;
}

sub compile_early { 1 }

sub method_call { '.' }
sub deref { '.' }
sub formatter_path { '/' }

sub parser_class { 'HTML::Template::Compiled::Parser' }

sub compiler_class { 'HTML::Template::Compiled::Compiler' }

sub quote_file {
    defined(my $f = $_[1]) or return '';
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


# -------- warning, ugly code
# i'm trading maintainability for efficiency here

sub try_global {
    my ( $self, $walk, $path ) = @_;
    my $stack = $self->get_globalstack || [];
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
    sub _walk_formatter {
        my ($self, $walk, $key, $global) = @_;
        my $ref = ref $walk;
        my $fm = $HTML::Template::Compiled::Formatter::formatter;
        my $sub = exists $fm->{$ref} ? $fm->{$ref}->{$key} : undef;
        my $stack = [];
        my $new_walk;
        if ($global) {
            $stack = $self->get_globalstack || [];
        }
        for my $item ($walk, reverse @$stack) {
            #print STDERR "::::::: formatter $walk -> $key (sub=$sub)\n";
            if (defined $sub) {
                $new_walk = $sub->($walk);
                last;
            }
            elsif (exists $item->{$key}) {
                #print STDERR "===== \$item->{$key} exists! '$item->{$key}'\n";
                $new_walk = $item->{$key};
                last;
            }
            # try next item in stack
        }
        #print STDERR "---- formatter $walk\n";
        return $new_walk;
    }

	# ----------- still ugly code
    # not needed anymore
#    if (my $formatter = $self->get_formatter() and $final and my $ref = ref $walk) {
#        if (my $sub = $formatter->{$ref}->{''}) {
#            my $return = $sub->($walk,$self,$P);
#            return $return unless ref $return;
#        }
#    }
#	return $walk;
}

# end ugly code, phooey

# returns if the var is valid
# fix 2007-07-23: HTML::Template allows every character
# although the documentation says it doesn't.
sub validate_var {
    return 1;
    #return $_[1] !~ tr{a-zA-Z0-9._[]/#-}{}c;
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

sub new_scalar_from_object {
    my ($self, $scalar) = @_;
    my $new = $self->clone;
    $new->set_includes({});
    $new->set_perl(undef);
    $new->set_filehandle();
    $new->set_cache(0);
    $new->set_cache_dir(undef);
    $new->set_scalar(\$scalar);
    my $md5 = md5($scalar);
    $new->set_filename($md5);
    $new = $new->from_scratch;
    return $new;
}
# create from existing object (TMPL_INCLUDE)
sub new_from_object {
    my ( $self, $path, $filename, $fullpath, $cache ) = @_;
    unless (defined $filename) {
        my ($file) = (caller(1))[3];
        croak "Filename is undef (in template $file)";
    }
    my $new = $self->clone;
    D && $self->log("new_from_object($path,$filename,$fullpath,$cache)");
    $new->set_filename($filename);
    #if ($fullpath) {
    #    $self->set_file($fullpath);
    #}
    $new->set_includes({});
    $new->set_scalar();
    $new->set_filehandle();
    my $md5path = md5_hex(@{ $path || [] });
    $new->set_path($path);
    $new->set_md5_path( $md5path );
    $new->set_perl(undef);
    if (my $cached = $new->from_cache) {
        $cached->set_plugins($self->get_plugins);
        $cached->init_includes;
        return $cached
    }
    $new = $new->from_scratch;
    $new->init_includes;
    return $new;
}

sub prepare_for_cache {
    my ($self) = @_;
    $self->clear_params;
    my @plugs = @{ $self->get_plugins || [] };
    for my $i (0 .. $#plugs) {
        if (ref $plugs[$i]) {
            if ($plugs[$i]->can('serialize')) {
                $plugs[$i] = $plugs[$i]->serialize();
            }
        }
    }
    $self->set_plugins(\@plugs);
}

sub preload {
    my ( $class, $dir ) = @_;
    opendir my $dh, $dir or die "Could not open '$dir': $!";
    my @files = grep { m/\.pl|\.storable$/ } readdir $dh;
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

sub get_param {
    return $_[0]->[PARAM];
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
            else {
                $self->[PARAM] = $_[0];
                return;
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

    if ( !$self->get_case_sensitive ) {
        my $lc = $self->lchash( {%p} );
        %p = %$lc;
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
    my $info = $self->get_parse_tree
        or do {
            $self->_error_no_query();
            return;
        };
    unless (ref $info) {
        # not compiled yet!
        $self->_error_not_compiled();
        return;
    }
    my $pointer = {children => $info};
    $tags = [] unless defined $tags;
    $tags = [$tags] unless ref $tags eq 'ARRAY';
    my $includes = $self->get_includes;
    my %include_info = map {
        $includes->{$_}->[1] => $includes->{$_}->[2]->get_parse_tree;
    } keys %{ $includes };
    for my $tag (@$tags) {
        my $value;
        my %includes = map {
            my $item = $pointer->{children}->{$_};
            ($item->{type} eq 'INCLUDE' and $include_info{$_})
                ? (%{$include_info{$_}})
                : ()
        } keys %{ $pointer->{children} };
        if (defined ($value = $pointer->{children}->{lc $tag})) {
            $pointer = $value;
        }
        elsif (defined ($value = $includes{lc $tag})) {
            $pointer = $value;
        }
        else {
            return;
        }
    }
    unless ($what) {
        my @return = map {
            my $item = $pointer->{children}->{$_};
            ($item->{type} eq 'INCLUDE' and $include_info{$_})
            ? (keys %{$include_info{$_}})
            : $_;
        } keys %{ $pointer->{children} };
        return @return;
    }
    elsif ($what eq 'name') {
        my $type = $pointer->{type};
        return $type;
    }
    elsif ($what eq 'loop') {
        if ($pointer->{type} eq 'LOOP') {
            my @return = map {
                my $item = $pointer->{children}->{$_};
                ($item->{type} eq 'INCLUDE' and $include_info{$_})
                ? (keys %{$include_info{$_}})
                : $_;
            } keys %{ $pointer->{children} };
            return @return;
        }
        else { croak "error: (@$tags) is not a LOOP" }
    }
    return;
}

# =head2 lchash
# 
#   my $capped_href = $self->lchash(\%href);
# 
# Input:
#     - hashref or arrayref of hashrefs
# 
# Output: Returns a reference to a cloned data structure where all the keys are
# capped. 
# 
# =cut

sub lchash {
    my ( $self, $data ) = @_;
    my $lc;
    if ( ref $data eq 'HASH' ) {
        for my $key ( keys %$data ) {
            my $uc_key = lc $key;
            my $val    = $self->lchash( $data->{$key} );
            $lc->{$uc_key} = $val;
        }
    }
    elsif ( ref $data eq 'ARRAY' ) {
        for my $item (@$data) {
            my $new = $self->lchash($item);
            push @$lc, $new;
        }
    }
    else {
        $lc = $data;
    }
    return $lc;
}

sub output {
    my ( $self, $fh ) = @_;
    my $p = $self->[PARAM] || {};
    # if we only have an object as parameter
    $p = ref $p eq 'HASH'
        ? \% { $p }
        : $p;
    my $f = $self->get_file;
    $fh = \*STDOUT unless $fh;
    if ($DEBUG) {
        my $output;
        eval {
            $output = $self->get_perl()->( $self, $p, \$p, $fh );
        };
        if ($@) {
            $LAST_EXCEPTION = $@;
            my $filename = $self->get_file;
            die "Error while executing '$filename': $@";
        }
        return $output;
    }
    else {
        $self->get_perl()->( $self, $p, \$p, $fh );
    }
}

sub import {
    my ( $class, %args ) = @_;
    if ( $args{compatible} ) {
        $class->CaseSensitive(0);
        $class->SearchPathOnInclude(0);
        $class->UseQuery(1);
    }
    elsif ( $args{speed} ) {
        # default at the moment
        $class->CaseSensitive(1);
        $class->SearchPathOnInclude(1);
        $class->UseQuery(0);
    }
    if (exists $args{short}) {
        __PACKAGE__->export_to_level(1, scalar caller(), 'HTC');
    }
}

sub ExpireTime {
    my ($class, $seconds) = @_;
    $NEW_CHECK = $seconds;
}

sub EnableSub {
    carp "Warning: Subref variables are not supported any more, use HTML::Template::Compiled::Classic instead";
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
    my $stack = $_[0]->get_globalstack;
    push @$stack, $_[1];
    $_[0]->set_globalstack($stack);
}

sub popGlobalstack {
    my $stack = $_[0]->get_globalstack;
    pop @$stack;
    $_[0]->set_globalstack($stack);
}


{
    my $lock_fh;

    sub lock {
        my $file = File::Spec->catfile( $_[0]->get_cache_dir, "lock" );
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


{
    my $loaded = 0;
    my $error = 0;
    sub require_storable {
        return 1 if $loaded;
        return 0 if $error;
        eval {
            require Storable;
        };
        if ($@) {
            $error = 1;
            return 0;
        }
        eval "use B::Deparse 0.61";
        if ($@) {
            $error = 1;
            return 0;
        }
        return 1;
    }
}

sub debug_code {
    my ($self, $html) = @_;
    my $perl = $self->get_perl;
    require B::Deparse;
    my $deparse = B::Deparse->new("-p", "-sC");
    my $body = $deparse->coderef2text($perl);
    my $filename = $self->get_file;
    #warn __PACKAGE__.':'.__LINE__.$".Data::Dumper->Dump([\$body], ['body']);
    my $message = '';
    if ($LAST_EXCEPTION and $LAST_EXCEPTION =~ m/at \(eval \d*\) line (\d+)\./) {
        my $rline = $1;
        my $line = $rline;
        $line--;
        my @lines = split m#$/#, $body;
        if ($line > $#lines) {
            $line = $#lines;
        }
        my $pre = $line > 0 ? join $/, @lines[0 .. $line - 1] : '';
        my $post = $line < $#lines ? join $/, @lines[$line + 1 .. $#lines] : '';
        my $error = "$/$/# ------------------- ERROR line $rline in template $filename -----------------$/";
        my $last = $LAST_EXCEPTION;
        $LAST_EXCEPTION =~ s#$/# #g;
        $error .= "# $last$/$lines[$line]$/";
        if ($html) {
            for ($pre, $error, $post) {
                s/</&lt;/g;
                s/>/&gt;/g;
            }
            $message = <<"EOM";
<table border="0" style="background-color: #eeeeee;"><tr><td><pre>$pre</pre></td></tr>
<tr><td style="background-color: #ffffff; color: #ff0000"><pre>$error</pre></td></tr>
<tr><td><pre>$post</pre></td></tr></table>
EOM
        }
        else {
            $message .= $pre;
            $message .= $error;
            $message .= $post;
        }
    }
    else {
        $message = $LAST_EXCEPTION;
    }
    return $message;

}

my $version_pod = <<'=cut';
=pod

=head1 NAME

HTML::Template::Compiled - Template System Compiles HTML::Template files to Perl code

=head1 VERSION

$VERSION = "0.95_002"

=cut

sub __test_version {
    my $v = __PACKAGE__->VERSION;
    my ($v_test) = $version_pod =~ m/VERSION\s*=\s*"(.+)"/m;
    no warnings;
    return $v == $v_test ? 1 : 0;
}

1;

__END__

=pod

=head1 SYNOPSIS

  use HTML::Template::Compiled speed => 1;
  # or for compatibility with HTML::Template
  # use HTML::Template::Compiled compatible => 1;
  # or use HTML::Template::Compiled::Classic
  my $htc = HTML::Template::Compiled->new(filename => 'test.tmpl');
  $htc->param(
    BAND => $name,
    ALBUMS => [
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

For a quick reference, see L<HTML::Template::Compiled::Reference>.
HTML::Template::Compiled is a templating module which can be used
for creating HTML but also plaintext or other output.

As the basic features work like in L<HTML::Template>, please get familiar
with its documentation before.

HTML::Template::Compiled (HTC) does not implement all features of
L<HTML::Template>, and
it has got some additional features which are explained below:
L<"ADDITIONAL FEATURES">

HTML::Template::Compiled (HTC) is a template system which uses the same
template syntax as HTML::Template and the same perl API (see L<"COMPATIBILITY">
for what you need to know if you want (almost) the same behaviour). Internally
it works different, because it turns the template into perl code,
and once that is done, generating the output is much faster than with
HTML::Template (please see L<"BENCHMARKS"> for some examples, because a
comparison depends on so much parameters).
But you should run in a persistent environment like mod_perl oder FastCGI,
otherwise it might be even slower.

You might want to use L<HTML::Template::Compiled::Lazy> for CGI environments
as it doesn't parse the template before calling output. But note that HTC::Lazy
isn't much tested, and I don't use it myself, so there's a lack of experience.
If you use it and have problems, please report.

HTC will use a lot of memory because it keeps all template objects in memory.
If you are on mod_perl, and have a lot of templates, you should preload them at server
startup to be sure that it is in shared memory. At the moment HTC is not fully tested for
keeping all data in shared memory (e.g. when a copy-on-write occurs),
but it seems like it's behaving well.
For preloading you can use
  HTML::Template::Compiled->preload($dir).

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

Has a bug (doesn't return parameters in included files of included files).
I'm working on that.

=back

=head2 ADDITIONAL FEATURES

What can HTC do for you additionally to HTML::Template?

=over 4

=item TMPL_ELSIF

No need to have cascading "if-else-if-else"s

=item TMPL_EACH

Iterate over a hash. See L<"TMPL_EACH">

=item TMPL_WITH

see L<"TMPL_WITH">

=item TMPL_WHILE

see L<"TMPL_WHILE">

=item TMPL_COMMENT, TMPL_NOPARSE, TMPL_VERBATIM

see L<"TMPL_COMMENT">, L<"TMPL_NOPARSE">, L<"TMPL_VERBATIM">

=item C<__index__>

Additional loop variable (C<__counter__ -1>)

=item C<__break__>

Additional loop variable (see L<"TMPL_LOOP">)

=item C<__filename__>, C<__filenameshort__> (since 0.91_001)

Insert the template filename for debugging:

    <%= __filename__ %>
    <%= __filenameshort__ %>

will turn out as:
    templates/path/file.html
    path/file.html

See also option debug_file in L<"OPTIONS"> for adding the filename globally.

=item TMPL_SWITCH, TMPL_CASE

see L<"TMPL_SWITCH">

=item C<TMPL_PERL>

Include perl code in your template. See L<"RUNNING PERL WITH TMPL_PERL">

=item Chomp

Experimental feature, added in version 0.89. By using special tags the
newlines before and/or after the tags will be deleted.
I'm not sure about the syntax, so this might change. I'd be very glad about
comments. Example:

    my $htc = HTML::Template::Compiled->new(
        ...
        tagstyle => [qw/+asp_chomp/], # classic_chomp tt_chomp comment_chomp
    );
    template:
    <+-%= foo %>
    bar
    <-+%= baz %>
    is the same as
    <%= foo %>bar<%= baz %>

So C<+-> means, leave the newline in front alone, but chomp after it,
C<-+> is the opposite, C<--> chomps both and C<++> is just a no-op and
behaves like a normal tag.

=item Generating perl code

See L<"IMPLEMENTATION">

=item better variable access

dot-notation for accessing hash values. See L<"VARIABLE ACCESS">

=item rendering objcets

dot-notation for accessing object methods. See L<"RENDERING OBJECTS">

=item output to filehandle

See L<"OPTIONS">

=item Dynamic includes

C<INCLUDE_VAR>, C<INCLUDE_STRING>. See L<"INCLUDE">

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

=item Chained escaping

See L<"ESCAPING">

=item tagstyles

For those who like it (i like it because it is shorter than TMPL_), you
can use E<lt>% %E<gt> tags and the E<lt>%= tag instead of E<lt>%VAR (which will work, too):

 <%IF blah%>  <%= VARIABLE%>  <%/IF%>

Define your own tagstyles and/or deactivate predefined ones.
See L<"OPTIONS"> tagstyle.

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

As of version 0.69, subref variables are not supported any more with
HTML::Template::Compiled. Use L<HTML::Template::Compiled::Classic>
(contained in this distribution) instead. It provides most features
of HTC.

=item search_path_on_include

default is now 0, like in HTML::Template. Set it to 1 by
    HTML::Template::Compiled->SearchPathOnInclude(1);

=item use_query

default is 0 (off). Set it via
    HTML::Template::Compiled->UseQuery(1);

=item open_mode

If you want to have your templates read in utf-8, use

    open_mode => ':utf8',

as an option.

In the previous version, it was '<:utf8'. This is deprecated.

=back

To be compatible in all of the above options all use:

  use HTML::Template::Compiled compatible => 1;

If you don't care about these options you should use

  use HTML::Template::Compiled speed => 1;

which is the default but depending on user wishes that might change.

=head3 Different behaviour from HTML::Template

=over 4

=item Arrayrefs

At the moment this snippet

  <tmpl_if arrayref>true<tmpl_else>false</tmpl_if arrayref>

with this code:

    $htc->param(arrayref => []);

will print true in HTC and false in HTML::Template. In HTML::Template an
array is true if it has content, in HTC it's true if it (the reference) is
defined. I'll try to find a way to change that behaviour, though that might
be for the cost of speed.

As of L<HTML::Template::Compiled> 0.85 you can use this syntax:

    <tmpl_if arrayref# >true<tmpl_else>false</tmpl_if >

In L<HTML::Template::Compiled::Classic> 0.04 it works as in HTML::Template.

=item Searching the path

In HTML::Template, if you have a file a/b/c/d/template.html and in
that template you do an include of include.html, and include.html
is in /a/b/include.html, HTML::Template will find it. As this
wasn't so clear to me when reading the docs, I implemented
this differently. You'd either have to include ../../include.html,
or you should set search_path_on_include to 1 and include a/b/include.html.

If you really need this feature, write me. I'm still thinking of how
I would implement this, and I don't like it much, because it
seems to me like a global_vars for filenames, and I don't like
global_vars =)

=back

=head2 ESCAPING

Like in HTML::Template, you have C<ESCAPE=HTML>, C<ESCAPE=URL> and C<ESCAPE_JS>.
C<ESCAPE=HTML> will only escape '"&<>. If you want to escape more, use
C<ESCAPE=HTML_ALL>.
Additionally you have C<ESCAPE=DUMP>, which by default will generate a Data::Dumper output.

You can also chain different escapings, like C<ESCAPE=DUMP|HTML>.

=head2 INCLUDE

Additionally to

  <TMPL_INCLUDE NAME="file.htc">

you can do an include of a template variable:

  <TMPL_INCLUDE_VAR NAME="file_include_var">
  $htc->param(file_include_var => "file.htc");

Using C<INCLUDE VAR="..."> is deprecated.

You can also include strings:

    template:
    inc: <%include_string foo %>

    code:
    $htc->param(
        foo => 'included=<%= bar%>',
        bar => 'real',
    );

    output:
    inc: included=real

Note that included strings are not cached and cannot include files
or strings themselves.

  
=head2 EXTENDED VARIABLE ACCESS

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
    NAME => "Cool script",
  );

Now in the TMPL_LOOP C<ALBUMS> you would like to access the path to
your script, stored in $hash{SELF}. in HTML::Template you have to set
the option C<global_vars>, so you can access C<$hash{SELF}> from
everywhere. Unfortunately, now C<NAME> is also global, which might not
a problem in this simple example, but in a more complicated template
this is impossible. With HTC, you wouldn't use C<global_vars> here, but
you can say:

  <TMPL_VAR .SELF>

to access the root element, and you could even say C<.INFO.BIOGRAPHY>
or C<ALBUMS[0].SONGS[0].NAME> (the latter has changed since version 0.79)

=head2 RENDERING OBJECTS

This is still in development, so I might change the API here.

Additionally to feeding a simple hash do HTC, you can feed it objects.
To do method calls you can also use '.' in the template.

  my $htc = HTML::Template::Compiled->new(
    ...
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

I might stop supporting that you can set the values for method calls by setting
an option. Ideally I would like to have that behaviour changed only by inheriting.

=head2 RUNNING PERL WITH TMPL_PERL

Yes, templating systems are for separating code and templates. But
as it turned out to be implemented much easier than expressions i
decided to implement it. But expressions are also available with the option
C<use_expressions>.

Note: If you have templates that can be edited by untrustworthy persons then
you don't want them to include perl code.

So, how do you use the perl-tag? First, you have to set the option
C<use_perl> to C<1> when creating a template object.

Important note: don't use C<print> in the included code. Usually the
template code is concatenated and returned to your perl script.
To 'print' something out use

    __OUT__ 2**3;

This will be turned into something like

    $OUT .= 2**3;
    # or
    print $fh 2**3;

Important note 2: HTC does not parse Perl. if you use the
classic tag-delimiters like this:

    <tmpl_perl if (__CURRENT__->count > 42) { >

this will not work as it might seem. Use other delimiters
instead:

    <%perl if (__CURRENT__->count > 42) { %>

Example:

    <tmpl_loop list>
    <tmpl_perl unless (__INDEX__ % 3) { >
      </tr><tr>
    <tmpl_perl } >
    </tmpl_loop list>

    # takes the current position of the parameter
    # hash, key 'foo' and multiplies it with 3
    <%perl __OUT__ __CURRENT__->{foo} * 3; %>

List of special keywords inside a perl-tag:

=over 4

=item __OUT__

Is turned into C<$OUT .=> or C<print $fh>

=item __HTC__

Is turned into the variable containing the current template object.

=item __CURRENT__

Turned into the variable containing the current position
in the parameter hash.

=item __ROOT__

Turned into the variable containig the parameter hash.

=item __INDEX__

Turned into the current index of a loop (starting with 0).

=back

=head2 INHERITANCE

It's possible since version 0.69 to inherit from HTML::Template::Compiled.
It's just not documented, and internal method names might change in
the near future. I'll try to fix the API and document which methods
you can inherit.

=head3 METHODS TO INHERIT

=over 4

=item method_call

Default is C<sub method_call { '.' }>

=item deref

Default is C<sub deref { '.' }>

=item formatter_path

Deprecated, see L<HTML::Template::Compiled::Formatter> please.

=item compile_early

Define if every included file should be checked and parsed at compile time
of the including template or later when it is really used.

Default is C<sub compile_early { 1 }>

=item parser_class

Default is C<sub parser_class { 'HTML::Template::Compiled::Parser' }>

You can write your own parser class (which must inherit from
L<HTML::Template::Compiled::Parser>) and use this.

L<HTML::Template::Compiled::Lazy> uses this.

=back

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

Also you can give the current item an alias. See L<"ALIAS">. I also would like
to add a loop_context variable C<__current__>, if that makes sense.
Seems more readable to non perlers than C<_>.

The LOOP tag allows you to define a JOIN attribute:

 <tmpl_loop favourite_colors join=", ">
  <tmpl_var _ >
 </tmpl_loop>

This will output something like C<blue, pink, yellow>.
This is easier than doing:

 <tmpl_loop favourite_colors>
 <tmpl_unless __first__>, </tmpl_unless>
  <tmpl_var _ >
 </tmpl_loop>

The C<LOOP>, C<WHILE> and C<EACH> tags allow you to define a BREAK attribute:

 <tmpl_loop bingo break="3"> <tmpl_var _ ><if __break__>\n</if></tmpl_loop>

    $htc->param(bingo => [qw(X 0 _ _ X 0 _ _ X)]);

outputs

    X 0 _
    _ X 0
    _ _ X

So specifying BREAK=3 sets __break__ to 1 every 3rd loop iteration.

TMPL_LOOP expects an array reference, also if it is a method call. If
you want to iterate with TMPL_LOOP over a list from a method call, set
the attribute C<context=list>:

    <tmpl_loop object.list_method context=list>
        <tmpl_var _ >
    </tmpl_loop>

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

You also can use L<"ALIAS"> here.

=head2 TMPL_EACH

Iterating over a hash. Internally it is not implemented as an each, so you
can also sort the output:

    Sorted alphanumerically by default (since 0.93):
        <tmpl_each letters >
            <tmpl_var __key__ >:<tmpl_var __value__>
        </tmpl_each letters >
    Sorted numerically:
        <tmpl_each numbers sort=num >
            <tmpl_var __key__ >:<tmpl_var __value__>
        </tmpl_each numbers >
    Not sorted:
        <tmpl_each numbers sort=0 >
            <tmpl_var __key__ >:<tmpl_var __value__>
        </tmpl_each numbers >
    Sorted alphanumerically:
        <tmpl_each letters sort=alpha >
            <tmpl_var __key__ >:<tmpl_var __value__>
        </tmpl_each letters >

You have to set the option C<loop_context_vars> to true to use
the special vars C<__key__> and C<__value__>.

If you want to iterate over a hash instead of a hashref (some
methods might return plain hashes instead of references and
TMPL_EACH expects a ref), then you can set C<context=list>:

    <tmpl_each object.hash_method context=list>
    <tmpl_var __key__ >
    </tmpl_each>

=head2 TMPL_COMMENT

For debugging purposes you can temporarily comment out regions:

  Wanted: <tmpl_var wanted>
    <tmpl_comment outer>
    this won't be printed
      <tmpl_comment inner>
        <tmpl_var unwanted>
      </tmpl_comment inner>
      <tmpl_var unwanted>
  </tmpl_comment outer>

  $htc->param(unwanted => "no thanks", wanted => "we want this");

The output is (whitespaces stripped):

  Wanted: we want this

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

will not be recognized as template directives. Same syntax as
L<"TMPL_NOPARSE">, but it will be HTML-Escaped. This can be
useful for debugging.

=head2 TMPL_SWITCH

The SWITCH directive has the same syntax as VAR, IF etc.
The CASE directive takes a simple string or a comma separated list of strings.
Yes, without quotes. This will probably change! I just don't know yet
how it should look like. Suggestions?

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
Default is 0

=item file_cache

Set to 1 if you want to use file caching and specify the path
with file_cache_dir.

=item file_cache_dir

Path to caching directory (you have to create it before)

=item cache_dir

Replaced by file_cache_dir like in L<HTML::Template>. Will be deprecated
in future versions.

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

Vars like C<__first__>, C<__last__>, C<__inner__>, C<__odd__>, C<__counter__>,
C<__index__>

The variable C<__index__> works just like C<__counter__>, only that it starts
at 0 instead of 1.

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
    default_escape => 'HTML', # or URL
  );

Now everything will be escaped for HTML unless you explicitly specify C<ESCAPE=0> (no escaping)
or C<ESCAPE=URL>.

=item no_includes (since 0.92)

Default is 0. If set to 1, the tags INCLUDE, INCLUDE_VAR and INCLUDE_STRING
will cause a template syntax error when creating. This can be useful when opening
untrusted templates, otherwise any file in the filesystem could be opened.

=item debug_file (fixed) (since 0.91_001)

Additionally to the context_vars __filename__ and __filenameshort__ you
can enable filename debugging globally.

If the option is set to 'start', at the start of every template will be added:
    <!-- start templates/path/filename.html -->

If set to 'end', at the end will be added:
    <!-- end templates/path/filename.html -->

If set to 'start,end', both coments will be added.

If set to 'start,short', 'end,short' or 'start,end,short' the path
to the templates will be stripped:
    <!-- start path/filename.html -->
    <!-- end path/filename.html -->

=item objects (fixed) (since 0.91_001)

if set to true, you can use method calls like
    <%= object.method %>

Default is 'strict' (true).
If set to 'strict', the method will be called if we have an object, otherwise
it's treated as a hash lookup. If the method doesn't exist, it dies.
If set to 'nostrict', the method will be called only if the object 'can' do the
method, otherwise it will return undef (this will need Scalar::Util).
If set to 0, no method calls are allowed.

=item deref (fixed)

Deprecated. Please inherit and overwrite method 'deref'. See L<"INHERITANCE">

Define the string you want to use for dereferencing, default is C<.> at the
moment:

 <TMPL_VAR hash.key>

=item method_call (fixed)

Deprecated. Please inherit and overwrite method 'method_call'. See L<"INHERITANCE">

Define the string you want to use for method calls, default is . at
the moment:

 <TMPL_VAR object.method>

Don't use ->, though, like you could in earlier version. Var names can contain:
Numbers, letters, '.', '/', '+', '-' and '_', just like HTML::Template. Note that
if your var names contain dots, though, they will be treated as hash
dereferences. If you want literal dots, use L<HTML::Template::Compiled::Classic>
instead.
 
=item default_path (fixed)

Deprecated, see L<HTML::Template::Compiled::Formatter> please.

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

This option is deprecated as of version 0.76. You must now use a plugin instead, like
L<HTML::Template::Compiled::Plugin::DHTML>, for examle.

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
        qr({{), # start of opening tag
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

=item use_expressions (since 0.91_003)

Set to 1 if you want to use expressions. They work more or less like
in L<HTML::Template::Expr> - I took the parsing code from it and
used it with some minor changes - thanks to Sam Tregar.

    <%if expr="some.var > 3" %>It's grater than 3<%/if %>

Additionally you can use object methods with parameters. While a
normal method call can only be called without parameters, like

    <%= object.name %>

with expressions you can give it parameters:

    <%= expr="object.create_link('navi')" %>

Inside function and method calls you also can use template
vars.

It is only minimally tested yet, so use with care and please report any
bugs you find.

=item formatter

Deprecated, see L<HTML::Template::Compiled::Formatter> please.

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
  );
  # $obj is a Your::Class object
  $htc->param(obj => $obj);
  # Template:
  # Fullname: <tmpl_var obj/fullname>

=item formatter_path (fixed)

Deprecated, see L<HTML::Template::Compiled::Formatter> please.

=item debug

If set to 1 you will get the generated perl code on standard error

=item use_query

Set it to 1 if you plan to use the query() method. Default is 0.

Explanation: If you want to use query() to collect information
on the template HTC has to do extra-work while compiling and
uses extra-memory, so you can choose to save HTC work by
setting use_query to 0 (default) or letting HTC do the extra
work by setting it to 1. If you would like 1 to be the default,
write me. If enough people write me, I'll think abou it =)

=item use_perl

Set to 1 if you want to use the perl-tag. See L<"TMPL_PERL">. Default is 0.

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

Note: the directory is *not* the template directory. It should be the directory
which you give as the cache_dir option.

=item precompile

Class method. It will precompile a list of template files into the specified
cache directory. See L<"PRECOMPILE">.

=item clear_params

Empty all parameters.

=item debug_code (since 0.91_003)

If you get an error from the generated template, you might want to debug
the executed code. You can now call C<debug_code> to get the compiled code
and the line the error occurred. Note that the reported line might not be
the exact line where the error occurred, also look around the line.
The template filename reported does currently only report the main template,
not the name of an included template. I'll try to fix that.

    local $HTML::Template::Compiled::DEBUG = 1;
    my $htc = HTML::Template::Compiled->new(
        filename => 'some_file_with_runtime_error.html',
    );
    eval {
        print $htc->output;
    };
    if ($@) {
        # reports as text
        my $msg = $htc->debug_code;
        # reports as a html table
        my $msg_html = $htc->debug_code('html');
    }

=item get_plugin

    my $plugin = $htc->get_plugin('Name::of::plugin');

Returns the plugin object of that classname. If the plugin is only a string
(the classname itself), it returns this string, so this method is only
useful for plugin objects.

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

=head1 PLUGINS

At the moment you can use and write plugins for the C<ESCAPE> attribute. See
L<HTML::Template::Compiled::Plugin::XMLEscape> for an example how to
use it; and have a look at the source code if you want to know how to
write a plugin yourself.

Using Plugins:

    my $htc = HTML::Template::Compiled->new(
        ...
        plugin => ['HTML::Template::Compiled::Foo::Bar'],
        # oor shorter:
        plugin => ['::Foo::Bar'],
    );

=head1 LAZY LOADING

Let's say you're in a CGI environment and have a lot of includes in your
template, but only few of them are actually used. HTML::Template::Compiled
will (as L<HTML::Template> does) parse all of your includes at once.
Just like the C<use> function does in perl. To get a behaviour like
require, use L<HTML::Template::Compiled::Lazy>.


=head1 TODO

associate, methods with simple parameters,
expressions, pluggable, ...

=head1 IMPLEMENTATION

HTC generates a perl subroutine out of every template. Each included template
is a subroutine for itself. You can look at the generated code by activating
file caching and looking into the cache directory. When you call C<output()>,
the subroutine is called. The subroutine either creates a string and adds
each template text or the results of the tags to the string, or it prints
it directly to a filehandle. Because of the implementation you have to know
at creation time of the module if you want to get a string back or if you
want to print to a filehandle.

=head1 SECURITY

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

=head1 PRECOMPILE

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

On the other hand, compared to HTML::Template, you have a large speed gain under mod_perl
if you use case_sensitive = 1, loop_context_vars = 0,
With CGI HTC is slower.

See the C<examples/bench.pl> contained in this distribution.

Here are some examples from the benchmark script. I'm showing only Template::AutoFilter,
Template::HTML, HTML::Template and HTC. These four modules allow to set
automatic HTML escaping ('filter') for all variables.

 loop_context_vars 1
 global_vars 0
 case_sensitive 1
 default_escape HTML (respectively Template::AutoFilter and Template::HTML)

 ht: HTML::Template 2.10
 htc: HTML::Template::Compiled 0.95
 ttaf: Template::AutoFilter 0.112350 with Template 2.22
 tth: Template::HTML 0.02 with Template 2.22

First test is with the test.(htc|tt) from the examples directory, about 900 bytes.


Test without file cache and without memory cache.

              all_ht:  1 wallclock secs ( 0.40 usr +  0.00 sys =  0.40 CPU) @ 250.00/s (n=100)
             all_htc:  1 wallclock secs ( 1.74 usr +  0.01 sys =  1.75 CPU) @ 57.14/s (n=100)
 all_ttaf_new_object:  1 wallclock secs ( 1.69 usr +  0.01 sys =  1.70 CPU) @ 58.82/s (n=100)
  all_tth_new_object:  1 wallclock secs ( 1.44 usr +  0.00 sys =  1.44 CPU) @ 69.44/s (n=100)

With file cache:

              all_ht:  1 wallclock secs ( 1.03 usr +  0.01 sys =  1.04 CPU) @ 379.81/s (n=395)
             all_htc:  1 wallclock secs ( 1.07 usr +  0.00 sys =  1.07 CPU) @ 260.75/s (n=279)
 all_ttaf_new_object:  1 wallclock secs ( 1.07 usr +  0.04 sys =  1.11 CPU) @ 251.35/s (n=279)
  all_tth_new_object:  1 wallclock secs ( 1.01 usr +  0.04 sys =  1.05 CPU) @ 227.62/s (n=239)

With memory cache:

       all_ht:  1 wallclock secs ( 1.04 usr +  0.00 sys =  1.04 CPU) @ 461.54/s (n=480)
      all_htc:  1 wallclock secs ( 1.05 usr +  0.01 sys =  1.06 CPU) @ 3168.87/s (n=3359)
 process_ttaf:  1 wallclock secs ( 1.04 usr +  0.00 sys =  1.04 CPU) @ 679.81/s (n=707)
  process_tth:  1 wallclock secs ( 1.05 usr +  0.00 sys =  1.05 CPU) @ 609.52/s (n=640)


Now I'm using a template with about 18Kb by multiplying the example template
20 times. You can see that everything is running slower but some run more
slower than others.

Test without file cache and without memory cache.


              all_ht:  8 wallclock secs ( 7.57 usr +  0.04 sys =  7.61 CPU) @ 13.14/s (n=100)
             all_htc: 32 wallclock secs (32.08 usr +  0.06 sys = 32.14 CPU) @  3.11/s (n=100)
 all_ttaf_new_object: 36 wallclock secs (36.21 usr +  0.04 sys = 36.25 CPU) @  2.76/s (n=100)
  all_tth_new_object: 29 wallclock secs (28.92 usr +  0.05 sys = 28.97 CPU) @  3.45/s (n=100)

With file cache:

              all_ht:  8 wallclock secs ( 7.22 usr +  0.00 sys =  7.22 CPU) @ 13.85/s (n=100)
             all_htc:  5 wallclock secs ( 5.32 usr +  0.00 sys =  5.32 CPU) @ 18.80/s (n=100)
 all_ttaf_new_object:  8 wallclock secs ( 7.59 usr +  0.15 sys =  7.74 CPU) @ 12.92/s (n=100)
  all_tth_new_object:  9 wallclock secs ( 8.74 usr +  0.19 sys =  8.93 CPU) @ 11.20/s (n=100)

With memory cache:

       all_ht:  1 wallclock secs ( 1.04 usr +  0.01 sys =  1.05 CPU) @ 15.24/s (n=16)
      all_htc:  1 wallclock secs ( 1.12 usr +  0.00 sys =  1.12 CPU) @ 272.32/s (n=305)
 process_ttaf:  1 wallclock secs ( 1.07 usr +  0.00 sys =  1.07 CPU) @ 39.25/s (n=42)
  process_tth:  1 wallclock secs ( 1.05 usr +  0.00 sys =  1.05 CPU) @ 34.29/s (n=36)

So the performance difference highly depends on the size of the template and on the
various options.
You can see that using the 900byte template HTC is slower with file cache than
HTML::Template, but with the 18Kb template it's faster.


=head1 EXAMPLES

See L<examples/objects.html> (and C<examples/objects.pl>) for an example
how to feed objects to HTC.

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

I use it in my web applications, so I first write it for myself =)
If I can efficiently use it, it was worth it.

=head1 RESOURCES

See http://htcompiled.sf.net/ for svn access.

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

Special Thanks to Sascha Kiefer - he finds all the bugs!

Ronnie Neumann, Martin Fabiani, Kai Sengpiel, Jan Willamowius, Justin Day,
Steffen Winkler, Henrik Tougaard for ideas, beta-testing and patches

L<http://www.perlmonks.org/> and http://www.perl-community.de/> for everyday learning

Corion, Limbic~Region, tye, runrig and others from perlmonks.org 

=head1 COPYRIGHT AND LICENSE

Copyright (C) 2005 by Tina Mueller

This library is free software; you can redistribute it and/or modify
it under the same terms as Perl itself, either Perl version 5.8.3 or,
at your option, any later version of Perl 5 you may have available.


=cut
