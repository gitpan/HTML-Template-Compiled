package HTML::Template::Compiled::Compiler;
# $Id: Compiler.pm,v 1.44 2006/10/15 14:29:39 tinita Exp $
use strict;
use warnings;
use Data::Dumper;
use Carp qw(croak carp);
use HTML::Template::Compiled::Expression qw(:expressions);
use HTML::Template::Compiled::Utils qw(:walkpath);
use File::Basename qw(dirname);

our $VERSION = '0.05';

use Carp qw(croak carp);
use constant D             => 0;

use constant T_VAR         => 'VAR';
use constant T_IF          => 'IF';
use constant T_UNLESS      => 'UNLESS';
use constant T_ELSIF       => 'ELSIF';
use constant T_ELSE        => 'ELSE';
use constant T_IF_DEFINED  => 'IF_DEFINED';
use constant T_END         => '__EOT__';
use constant T_WITH        => 'WITH';
use constant T_SWITCH      => 'SWITCH';
use constant T_CASE        => 'CASE';
use constant T_INCLUDE     => 'INCLUDE';
use constant T_LOOP        => 'LOOP';
use constant T_WHILE       => 'WHILE';
use constant T_INCLUDE_VAR => 'INCLUDE_VAR';

use constant INDENT        => '    ';

use constant NO_TAG        => 0;
use constant OPENING_TAG   => 1;
use constant CLOSING_TAG   => 2;

use constant ATTR_ESCAPES    => 0;
use constant ATTR_TAGS       => 1;

sub set_escapes    { $_[0]->[ATTR_ESCAPES] = $_[1] }
sub get_escapes    { $_[0]->[ATTR_ESCAPES] }
sub set_tags       { $_[0]->[ATTR_TAGS] = $_[1] }
sub get_tags       { $_[0]->[ATTR_TAGS] }

sub add_escapes {
    my ($self, $new_escapes) = @_;
    my $escapes = $self->get_escapes;
    for my $key (%$new_escapes) {
        my $sub = $new_escapes->{$key};
        if (ref $sub eq 'CODE') {
            my $subname = "HTML::Template::Compiled::Compiler::subs::$key";
            no strict 'refs';
            *$subname = $sub;
            $escapes->{$key} = $subname;
        }
        else {
            $escapes->{$key} = $sub;
        }
    }
}

sub new {
    my $class = shift;
    my $self = [];
    bless $self, $class;
    $self->set_escapes({});
    return $self;
}

sub _escape_expression {
    my ( $self, $exp, $escape ) = @_;
    return $exp unless $escape;
    my @escapes = split m/\|/, uc $escape;
    my $escapes = $self->get_escapes();
    for (@escapes) {
        if ( $_ eq 'HTML' ) {
            $exp =
                _expr_function( 'HTML::Template::Compiled::Utils::escape_html',
                $exp, );
        }
        elsif ( $_ eq 'URL' ) {
            $exp =
                _expr_function( 'HTML::Template::Compiled::Utils::escape_uri',
                $exp, );
        }
        elsif ( $_ eq 'JS' ) {
            $exp =
                _expr_function( 'HTML::Template::Compiled::Utils::escape_js',
                $exp, );
        }
        elsif ( $_ eq 'DUMP' ) {
            $exp = _expr_method( 'dump', _expr_literal('$t'), $exp, );
        }
        elsif (my $sub = $escapes->{$_}) {
            $exp = _expr_function( $sub, $exp );
        }
    } ## end for (@escapes)
    return $exp;
} ## end sub _escape_expression

sub parse_var {
    my ( $self, $t, %args ) = @_;
    my $lexicals = $args{lexicals};
    my $context = $args{context};
    # only allow '.', '/', '+', '-' and '_'
    if (!$t->validate_var($args{var})) {
        $t->get_parser->_error_wrong_tag_syntax(
            $context->get_file, $context->get_line, "", $args{var}
        );
    }
    if ( grep { defined $_ && $args{var} eq $_ } @$lexicals ) {
        return "\$$args{var}";
    }
    my $root         = 0;
    my %loop_context = (
        __index__   => '$__ix__',
        __counter__ => '$__ix__+1',
        __first__   => '$__ix__ == $[',
        __last__    => '$__ix__ == $size',
        __odd__     => '!($__ix__ & 1)',
        __inner__   => '$__ix__ != $[ && $__ix__ != $size',
    );
    if ( $t->get_loop_context && $args{var} =~ m/^__(\w+)__$/ ) {
        if (exists $loop_context{ lc $args{var} }) {
            my $lc = $loop_context{ lc $args{var} };
            return $lc;
        }
    }
    my $re = qr#
        \Q$args{deref}\E |
        \Q$args{method_call}\E |
        \Q$args{formatter_path}\E
        #x;
    my $up_stack = 0;
    my $varstr = 'do {my $var = $$C; ';
    if ( $args{var} =~ m/^_/ && $args{var} !~ m/^__(\w+)__$/ ) {
        $args{var} =~ s/^_//;
        $root = 0;
    }
    elsif ( my @roots = $args{var} =~ m/\G($re)/gc) {
        #print STDERR "ROOTS: (@roots)\n";
        $root = 1 if @roots == 1;
        $args{var} =~ s/^($re)+//;
        if (@roots > 1) {
            croak "Cannot navigate up the stack" if !$t->get_global_vars & 2;
            $up_stack = $#roots;
            $varstr .= <<"EOM";
my \$stack = \$t->get_globalstack;
\$var = \$stack->[-$up_stack]; #print \$var, \$/;
EOM
        }
        elsif (@roots == 1) {
            $varstr .= q#$var = $P;#;
        }
    }
    my @split = split m/(?=$re)/, $args{var};
    @split = map {
        m/(.*)\[(-?\d+)\]/ ? ("$1", "[$2]") : $_
    } @split;
    my @paths;
    #print STDERR "paths: (@split)\n";
    my $count = 0;
    for my $p (@split) {
        $p =~ s#\\#\\\\#g;
        $p =~ s#'#\\'#g;
        next unless length $p;
        #print STDERR "path: $p\n";
        if ( $p =~ s/^\[(-?\d+)\]$/$1/ ) {
            $varstr .= "\$var = \$var->[$1];\n";
        }
        elsif ( $p =~ s/^\Q$args{method_call}// ) {
            if ($count == 0 && $t->get_global_vars & 1) {
                $varstr .= "\$var = \$t->try_global(\$var, '$p');\n";
            }
            else {
                my $path = $t->get_case_sensitive ? $p : uc $p;
            $varstr .= <<"EOM";
\$var = UNIVERSAL::can(\$var,'$p') ? UNIVERSAL::can(\$var,'$p')->(\$var) : \$var->\{'$path'\};
EOM
            }
        }
        elsif ( $p =~ s/^\Q$args{deref}// ) {
            #print STDERR "$p deref\n";
            if ($count == 0 && $t->get_global_vars & 1) {
                $varstr .= "\$var = \$t->try_global(\$var, '$p');\n";
            }
            else {
                my $path = $t->get_case_sensitive ? $p : uc $p;
            $varstr .= <<"EOM";
\$var = UNIVERSAL::can(\$var,'$p') ? UNIVERSAL::can(\$var,'$p')->(\$var) : \$var->\{'$path'\};
EOM
            }
        } ## end elsif ( $p =~ s/^\Q$args{deref}//)
        elsif ( $p =~ s/^\Q$args{formatter_path}// ) {

            $varstr .= <<"EOM";
            \$var = \$t->_walk_formatter(\$var, '$p', @{[$t->get_global_vars]});
EOM
        } ## end elsif ( $p =~ s/^\Q$args{formatter_path}//)
        else {
            if ($count == 0 && $t->get_global_vars & 1) {
                $varstr .= "\$var = \$t->try_global(\$var, '$p');\n";
            }
            else {
                my $path = $t->get_case_sensitive ? $p : uc $p;
                $varstr .= <<"EOM";
\$var = UNIVERSAL::can(\$var,'$p') ? UNIVERSAL::can(\$var,'$p')->(\$var) : \$var->\{'$path'\};
EOM
            }
        } ## end else [ if ( $p =~ s/^\Q$args{method_call}//)
        $count++;
    } ## end for my $p (@split)
    #my $final = $context->get_name eq 'VAR' ? 1 : 0;
        $varstr .= <<'EOM';
$var }
EOM
    return $varstr;
} ## end sub parse_var

sub compile {
    my ( $class, $self, $text, $fname ) = @_;
    D && $self->log("compile($fname)");
    if ( my $filter = $self->get_filter ) {
        $filter->filter($text);
    }
    my $parser = $self->get_parser;
    my @p = $parser->parse($fname, $text);
    my $level = 1;
    my $code  = '';
    my $info = {}; # for query()
    my $info_stack = [$info];

    # got this trick from perlmonks.org
    my $anon = D
      || $self->get_debug ? qq{local *__ANON__ = "htc_$fname";\n} : '';

    no warnings 'uninitialized';
    my $output = '$OUT .= ';
    my $out_fh = $self->get_out_fh;
    if ($out_fh) {
        $output = 'print $OFH ';
    }
    my $header = <<"EOM";
sub {
    use vars '\$__ix__';
    no warnings;
$anon
    my (\$t, \$P, \$C, \$OFH) = \@_;
    my \$OUT = '';
    #my \$C = \\\$P;
EOM

    my @lexicals;
    my @switches;
    my $tags = $class->get_tags;
    for my $token (@p) {
        my ($text, $line, $open, $tname, $attr, $close) = @$token;
        #print STDERR "tags: ($text, $line, $open, $tname, $attr, $close)\n";
        #print STDERR "p: '$text'\n";
        my $indent = INDENT x $level;
        my $meth     = $self->method_call;
        my $deref    = $self->deref;
        my $format   = $self->formatter_path;
        my %var_args = (
            deref          => $deref,
            method_call    => $meth,
            formatter_path => $format,
            lexicals       => \@lexicals,
        );
        if (!$token->is_tag) {
            if ( length $text ) {
                my $exp = _expr_string($text);
                $code .= qq#$indent$output # . $exp->to_string($level) . $/;
            }
        }
        elsif ($token->is_open) {
        # --------- TMPL_VAR
        if ($tname eq T_VAR) {
            my $var    = $attr->{NAME};
            if ($self->get_use_query) {
                $info_stack->[-1]->{lc $var}->{type} = T_VAR;
            }
            my $expr;
            if (exists $tags->{$tname} && exists $tags->{$tname}->{open}) {
                $expr = $tags->{$tname}->{open}->($class, $self, {
                        %var_args,
                        context => $token,
                    },);
            }
            else {
               $expr = $class->_compile_OPEN_VAR($self, {
                        %var_args,
                        context => $token,
                    },);
            }
            $code .= qq#${indent}$output #
            . $expr->to_string($level) . qq#;\n#;
        }
        # --------- TMPL_WITH
        elsif ($tname eq T_WITH) {
            $level++;
            my $var    = $attr->{NAME};
            my $varstr = $class->parse_var($self,
                %var_args,
                var => $var,
                context => $token,
            );
            $code .= _expr_open()->to_string($level) .qq# \# WITH $var\n#;
            if ($self->get_global_vars) {
                $code .= _expr_method(
                    'pushGlobalstack',
                    _expr_literal('$t'),
                    _expr_literal('$$C')
                )->to_string($level) . ";\n";
            }
            $code .= qq#${indent}  my \$C = \\$varstr;\n#;
        }

        # --------- TMPL_LOOP TMPL_WHILE
        elsif ( ($tname eq T_LOOP || $tname eq T_WHILE) ) {
            my $var     = $attr->{NAME};
            my $varstr = $class->parse_var($self,
                %var_args,
                var   => $var,
                context => $token,
            );
            $level += 2;
            my $ind    = INDENT;
            if ($self->get_use_query) {
                $info_stack->[-1]->{lc $var}->{type} = T_LOOP;
                $info_stack->[-1]->{lc $var}->{children} ||= {};
                push @$info_stack, $info_stack->[-1]->{lc $var}->{children};
            }
            my $lexical = $attr->{ALIAS};
            push @lexicals, $lexical;
            my $pop_global = _expr_method(
                'pushGlobalstack',
                _expr_literal('$t'),
                _expr_literal('$$C')
            );
            my $lexi =
              defined $lexical ? "${indent}my \$$lexical = \$\$C;\n" : "";
            my $global = $self->get_global_vars
                ? $pop_global->to_string($level).";\n"
                : '';
            if ($tname eq T_WHILE) {
                $code .= _expr_open()->to_string($level) . "# while $var\n";
                $code .= <<"EOM";
$global
${indent}${indent}local \$__ix__ = -1;
${indent}${ind}while (my \$next = $varstr) {
${indent}${indent}\$__ix__++;
${indent}${indent}my \$C = \\\$next;
$lexi
EOM
            }
            else {

                $code .= <<"EOM";
${indent}if (UNIVERSAL::isa(my \$array = $varstr, 'ARRAY') )\{
${indent}${ind}my \$size = \$#{ \$array };
$global

${indent}${ind}# loop over $var
${indent}${ind}for \$__ix__ (\$[..\$size + \$[) \{
${indent}${ind}${ind}my \$C = \\ (\$array->[\$__ix__]);
$lexi
EOM
            }
        }

        # --------- TMPL_ELSE
        elsif ($tname eq T_ELSE) {
            my $exp = _expr_else();
            $code .= $exp->to_string($level);
        }

        # --------- TMPL_IF TMPL_UNLESS TMPL_ELSIF TMPL_IF_DEFINED
        elsif ($tname eq T_IF) {
            my $expr = $class->_compile_OPEN_IF($self, {
                    %var_args,
                    context => $token,
                },);
            $code .= $expr->to_string($level);
            $level++;
        }
        elsif ($tname eq T_IF_DEFINED) {
            my $expr = $class->_compile_OPEN_IF_DEFINED($self, {
                    %var_args,
                    context => $token,
                },);
            $code .= $expr->to_string($level);
            $level++;
        }
        elsif ($tname eq T_UNLESS) {
            my $expr = $class->_compile_OPEN_UNLESS($self, {
                    %var_args,
                    context => $token,
                },);
            $code .= $expr->to_string($level);
            $level++;
        }

        # --------- TMPL_ELSIF
        elsif ($tname eq T_ELSIF) {
            my $var    = $attr->{NAME};
            my $varstr = $class->parse_var($self,
                %var_args,
                var   => $var,
                context => $token,
            );
            my $operand = _expr_literal($varstr);
            my $exp = _expr_elsif($operand);
            my $str = $exp->to_string($level);
            $code .= $str . $/;
        }

        # --------- TMPL_SWITCH
        elsif ($tname eq T_SWITCH) {
            my $var = $attr->{NAME};
            push @switches, 0;
            $level++;
            my $varstr = $class->parse_var($self,
                %var_args,
                var   => $var,
                context => $token,
            );
            $code .= <<"EOM";
${indent}SWITCH: for my \$_switch ($varstr) \{
EOM
        }
        
        # --------- TMPL_CASE
        elsif ($tname eq T_CASE) {
            my $val = $attr->{NAME};
            #$val =~ s/^\s+//;
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
        elsif ($tname =~ m/^INCLUDE/) {
            my $filename;
            my $varstr;
            my $path = $self->get_path();
            my $dir;
            my $dynamic = $tname eq T_INCLUDE_VAR ? 1 : 0;
            my $fullpath = "''";

            if ($dynamic) {
                # dynamic filename
                my $dfilename = $attr->{NAME};
                if ($self->get_use_query) {
                    $info_stack->[-1]->{lc $dfilename}->{type} = T_INCLUDE_VAR;
                }
                $varstr = $class->parse_var($self,
                    %var_args,
                    var   => $dfilename,
                    context => $token,
                );
            }
            else {
                # static filename
                $filename = $attr->{NAME};
                if ($self->get_use_query) {
                    $info_stack->[-1]->{lc $filename}->{type} = T_INCLUDE;
                }
                $varstr   = $self->quote_file($filename);
                $dir      = dirname $fname;
                if ($self->get_search_path) {
                    if ( defined $dir and !grep { $dir eq $_ } @$path ) {
                        # add the current directory to top of paths
                        # create new $path, don't alter original ref
                        $path = [ $dir, @$path ] ;
                    }
                }
                else {
                        $path = [ $dir ] ;
                }
                # generate included template
                {
                    D && $self->log("compile include $filename!!");
                    $self->compile_early() and my $cached_or_new
                        = $self->new_from_object(
                          $path, $filename, '', $self->get_cache_dir
                      );
                    $fullpath = $cached_or_new->get_file;
                    $self->get_includes()->{$fullpath}
                        = [$path, $filename, $cached_or_new];
                        $fullpath = $self->quote_file($fullpath);
                }
            }
            #print STDERR "include $varstr\n";
            my $cache = $self->get_cache_dir;
            $path = defined $path
              ? '['
              . join( ',', map { $self->quote_file($_) } @$path ) . ']'
              : 'undef';
            $cache = defined $cache ? $self->quote_file($cache) : 'undef';
            if ($dynamic) {
                $code .= <<"EOM";
${indent}\{
${indent}  if (defined (my \$file = $varstr)) \{
${indent}    my \$include = \$t->get_includes()->{$fullpath};
${indent}    my \$new = \$include ? \$include->[2] : undef;
#print STDERR "+++++++got new? \$new\\n";
${indent}    if (!\$new || HTML::Template::Compiled::needs_new_check($cache||'',\$file)) {
${indent}      \$new = \$t->new_from_object($path,\$file,$fullpath,$cache);
${indent}    }
#print STDERR "got new? \$new\\n";
${indent}    \$new->set_globalstack(\$t->get_globalstack);
${indent}    $output \$new->get_code()->(\$new,\$P,\$C@{[$out_fh ? ",\$OFH" : '']});
${indent}  \}
${indent}\}
EOM
            }
            else {
                $code .= <<"EOM";
${indent}\{
${indent}    my \$include = \$t->get_includes()->{$fullpath};
${indent}    my \$new = \$include ? \$include->[2] : undef;
#print STDERR "got new? \$new\\n";
${indent}    if (!\$new) {
${indent}      \$new = \$t->new_from_object($path,$varstr,$fullpath,$cache);
${indent}    }
#print STDERR "got new? \$new\\n";
${indent}    \$new->set_globalstack(\$t->get_globalstack);
${indent}    $output \$new->get_code()->(\$new,\$P,\$C@{[$out_fh ? ",\$OFH" : '']});
${indent}\}
EOM
            }
        }
        else {
            # user defined
            #warn Data::Dumper->Dump([\$token], ['token']);
            #warn Data::Dumper->Dump([\$tags], ['tags']);
            my $subs = $tags->{$tname};
            if ($subs && $subs->{open}) {
                $code .= $subs->{open}->($self, $token, {
                        out => $output,
                });
            }
        }
        }
        elsif ($token->is_close) {
        # --------- / TMPL_IF TMPL UNLESS TMPL_WITH
        if ($tname =~ m/^(?:IF|UNLESS|WITH)$/) {
            my $var = $attr->{NAME};
            $var = '' unless defined $var;
            #print STDERR "============ IF ($text)\n";
            $level--;
            my $indent = INDENT x $level;
            my $exp = _expr_close();
            $code .= $exp->to_string($level) . qq{# end $var\n};
            if ($self->get_global_vars && $tname eq 'WITH') {
                $code .= $indent . qq#\$t->popGlobalstack;\n#;
            }
        }

        # --------- / TMPL_SWITCH
        elsif ($tname eq T_SWITCH) {
            $level--;
            my $close = _expr_close();
            if ( $switches[$#switches] ) {

                # we had at least one CASE, so we close the last if
                $code .= $close->to_string($level+1) . " # last case\n";
            }
            $code .= $close->to_string($level) . "\n";
            pop @switches;
        }
        
        # --------- / TMPL_LOOP TMPL_WHILE
        elsif ($tname eq T_LOOP || $tname eq T_WHILE) {
            pop @lexicals;
            if ($self->get_use_query) {
                pop @$info_stack;
            }
            my $close = _expr_close();
            $level-= 2;
            my $indent = INDENT x $level;
            $code .= $close->to_string($level+1) ."\n" 
                . $close->to_string($level) . " # end loop\n";
            if ($self->get_global_vars) {
            $code .= <<"EOM";
${indent}\$t->popGlobalstack;
EOM
            }
        }
        }

    }
    if ($self->get_use_query) {
        $self->set_use_query($info);
    }
    #warn Data::Dumper->Dump([\$info], ['info']);
    $code .= qq#return \$OUT;\n#;
    $code = $header . $code . "\n} # end of sub\n";

    #$code .= "\n} # end of sub\n";
    print STDERR "# ----- code \n$code\n# end code\n" if $self->get_debug;

    # untaint code
    if ( $code =~ m/(\A.*\z)/ms ) {
        # we trust our template
        $code = $1;
    }
    else {
        $code = "";
    }
    my $l = length $code;
    #print STDERR "length $fname: $l\n";
    my $sub = eval $code;
    #die "code: $@ ($code)" if $@;
    die "code: $@" if $@;
    return $code, $sub;
}
sub _compile_OPEN_VAR {
        my ($self, $htc, $args) = @_;
    #print STDERR "===== VAR ($text)\n";
    my $token = $args->{context};
    my $attr = $token->get_attributes;
    my $var = $attr->{NAME};
    my $varstr = $self->parse_var($htc,
        %$args,
        var   => $var,
        context => $token,
    );
    #print "line: $text var: $var ($varstr)\n";
    my $exp = _expr_literal($varstr);
    # ---- default
    my $default;
    if (exists $attr->{DEFAULT}) {
        $default = _expr_string($attr->{DEFAULT});
    }
    if ( defined $default ) {
        $exp = _expr_ternary(
            _expr_defined($exp),
            $exp,
            $default,
        );
    }
    # ---- escapes
    my $escape = $htc->get_default_escape;
    if (exists $attr->{ESCAPE}) {
        $escape = $attr->{ESCAPE};
    }
    $exp = $self->_escape_expression($exp, $escape);
    return $exp;
}

sub _compile_OPEN_IF {
    my ($self, $htc, $args) = @_;
    #print STDERR "============ IF ($text)\n";
    my $var = $args->{context}->get_attributes->{NAME};
    my $varstr = $self->parse_var($htc,
        %$args,
        var   => $var,
    );
    my $operand = _expr_literal($varstr);
    my $expr = HTML::Template::Compiled::Expression::If->new($operand);
    return $expr;
}
sub _compile_OPEN_UNLESS {
    my ($self, $htc, $args) = @_;
    #print STDERR "============ IF ($text)\n";
    my $var = $args->{context}->get_attributes->{NAME};
    my $varstr = $self->parse_var($htc,
        %$args,
        var   => $var,
    );
    my $operand = _expr_literal($varstr);
    my $expr = HTML::Template::Compiled::Expression::Unless->new($operand);
    return $expr;
}
sub _compile_OPEN_IF_DEFINED {
    my ($self, $htc, $args) = @_;
    #print STDERR "============ IF ($text)\n";
    my $var = $args->{context}->get_attributes->{NAME};
    my $varstr = $self->parse_var($htc,
        %$args,
        var   => $var,
    );
    my $operand = _expr_literal($varstr);
    $operand = _expr_defined($operand);
    my $expr = HTML::Template::Compiled::Expression::If->new($operand);
    return $expr;
}

1;

__END__

=pod

=head1 NAME

HTML::Template::Compiled::Compiler - Compiler class for HTC

=cut

