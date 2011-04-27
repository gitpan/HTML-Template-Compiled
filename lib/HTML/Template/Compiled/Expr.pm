package HTML::Template::Compiled::Expr;
# $Id: Expr.pm 1050 2008-06-16 20:27:20Z tinita $
use strict;
use warnings;
use Carp qw(croak carp);
use HTML::Template::Compiled::Expression qw(:expressions);
use HTML::Template::Compiled;
use Parse::RecDescent;
our $VERSION = '0.04';
HTML::Template::Compiled->register('HTML::Template::Compiled::Expr');

my $default_validate = sub { exists $_[1]->{NAME} or exists $_[1]->{EXPR} };
sub register {
    my ($class) = @_;
    my %plugs = (
        tagnames => {
            HTML::Template::Compiled::Token::OPENING_TAG() => {
                VAR => [ $default_validate, qw(NAME EXPR ESCAPE DEFAULT) ],
                '=' => [ $default_validate, qw(NAME EXPR ESCAPE DEFAULT) ],
                IF  => [ $default_validate, qw(NAME EXPR) ],
                IF_DEFINED => [ $default_validate, qw(NAME EXPR) ],
                ELSIF      => [ $default_validate, qw(NAME EXPR) ],
                UNLESS     => [ $default_validate, qw(NAME EXPR) ],
                WITH       => [ $default_validate, qw(NAME EXPR) ],
                LOOP       => [ $default_validate, qw(NAME EXPR ALIAS) ],
                WHILE      => [ $default_validate, qw(NAME EXPR ALIAS) ],
            },
            HTML::Template::Compiled::Token::CLOSING_TAG() => {
                IF         => [ undef, qw(NAME) ],
                IF_DEFINED => [ undef, qw(NAME) ],
                ELSIF      => [ undef, qw(NAME) ],
                UNLESS     => [ undef, qw(NAME) ],
                WITH       => [ undef, qw(NAME) ],
                LOOP       => [ undef, qw(NAME) ],
                WHILE      => [ undef, qw(NAME) ],
            },
        },
        compile => {
            VAR => {
                open => sub {
                    #            my ($htc, $token, $args) = @_;
    my ($compiler, $htc, $args) = @_;
    my $token = $args->{context};
    my $attr = $token->get_attributes;
    if (exists $attr->{NAME}) {
        return $compiler->_compile_OPEN_VAR($htc, $args);
    }
    my $var = $attr->{EXPR};
    my @tokens = parse_expr($var);
    my $OUT = $args->{out};
    for (@tokens) {
        next if $_->[0] ne 'var';
        my $varstr = $compiler->parse_var($htc,
            %$args,
            var   => $_->[1],
            context => $token,
        );
        $_->[1] = _expr_literal($varstr)->to_string;
    }
    my $string = '';
    for (@tokens) {
        $string .= $_->[1];
    }
    my $exp = _expr_literal($string);
    #print "line: $text var: $var ($varstr)\n";
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
    $exp = $compiler->_escape_expression($exp, $escape);
    return $exp;


                },
            },
        },
    );
    return \%plugs;
}

my $re = qr# (?:
    \b(?:eq | ne | ge | le | gt | lt )\b
    |
    (?: == | != | <= | >= | > | <)
    |
    (?: [0-9]+ )
    ) #x;

my $GRAMMAR = <<'END';
expression : paren /^$/  { $return = $item[1] } 

paren         : '(' binary_op ')'     { $item[2] }
              | '(' subexpression ')' { $item[2] }
            | subexpression         { $item[1] }
            | '(' paren ')'         { $item[2] }

subexpression : function_call
            | method_call
            | var
            | literal
            | <error>

binary_op     : paren (op paren { [ $item[2], $item[1] ] })(s)
            { $return = [ 'SUB_EXPR', $item[1], map { @$_ } @{$item[2]} ] }

op            : />=?|<=?|!=|==/      { [ 'BIN_OP',  $item[1] ] }
            | /le|ge|eq|ne|lt|gt/  { [ 'BIN_OP',  $item[1] ] }
            | /\|\||or|&&|and/     { [ 'BIN_OP',  $item[1] ] }
            | /[-+*\/%.]/           { [ 'BIN_OP',  $item[1] ] }


method_call : var '(' args ')' { [ 'METHOD_CALL', $item[1], $item[3] ] }

function_call : function_name '(' args ')'  
            { [ 'FUNCTION_CALL', $item[1], $item[3] ] }
            | function_name ...'(' paren
            { [ 'FUNCTION_CALL', $item[1], [ $item[3] ] ] }
            | function_name '(' ')'
            { [ 'FUNCTION_CALL', $item[1] ] }

function_name : /[A-Za-z_][A-Za-z0-9_]*/

args          : <leftop: paren ',' paren>

var           : /[.\/A-Za-z_][.\/\[\]A-Za-z0-9_]*/ { [ 'VAR', $item[1] ] }

literal       : /-?\d*\.\d+/             { [ 'LITERAL', $item[1] ] }
            | /-?\d+/                  { [ 'LITERAL', $item[1] ] }
            | <perl_quotelike>         { [ 'LITERAL_STRING', $item[1][1], $item[1][2] ] }

END
my %FUNC = (
    'sprintf' => sub { sprintf( shift, @_ ); },
    'substr'  => sub {
        return substr( $_[0], $_[1] ) if @_ == 2;
        return substr( $_[0], $_[1], $_[2] );
    },
    'lc'      => sub { lc( $_[0] ); },
    'lcfirst' => sub { lcfirst( $_[0] ); },
    'uc'      => sub { uc( $_[0] ); },
    'ucfirst' => sub { ucfirst( $_[0] ); },
    'length'  => sub { length( $_[0] ); },
    'defined' => sub { defined( $_[0] ); },
    'abs'     => sub { abs( $_[0] ); },
    'atan2'   => sub { atan2( $_[0], $_[1] ); },
    'cos'     => sub { cos( $_[0] ); },
    'exp'     => sub { exp( $_[0] ); },
    'hex'     => sub { hex( $_[0] ); },
    'int'     => sub { int( $_[0] ); },
    'log'     => sub { log( $_[0] ); },
    'oct'     => sub { oct( $_[0] ); },
    'rand'    => sub { rand( $_[0] ); },
    'sin'     => sub { sin( $_[0] ); },
    'sqrt'    => sub { sqrt( $_[0] ); },
    'srand'   => sub { srand( $_[0] ); },
);
# under construction
my $DEFAULT_PARSER;
sub parse_expr {
    my ($class, $compiler, $htc, %args) = @_;
    #warn __PACKAGE__.':'.__LINE__.$".Data::Dumper->Dump([\%args], ['args']);
    my $string = $args{expr};
    my $PARSER = $DEFAULT_PARSER ||= Parse::RecDescent->new($GRAMMAR);
    #warn __PACKAGE__.':'.__LINE__.$".Data::Dumper->Dump([\$string], ['string']);
    my $tree = $PARSER->expression("( $string )");
#    warn Data::Dumper->Dump([\$tree], ['tree']);
    my $expr = $class->sub_expression($tree, $compiler, $htc, %args);
#    warn __PACKAGE__.':'.__LINE__.$".Data::Dumper->Dump([\$expr], ['expr']);
    return $expr;

}

sub sub_expression {
    my ($class, $tree, $compiler, $htc, %args) = @_;
    my ($type, @args) = @$tree;
    #warn __PACKAGE__.':'.__LINE__.": $type\n";
    #warn __PACKAGE__.':'.__LINE__.$".Data::Dumper->Dump([\$tree], ['tree']);
    if ($type eq 'SUB_EXPR') {
        my $op = pop @args;
        #warn __PACKAGE__.':'.__LINE__.$".Data::Dumper->Dump([\$op], ['op']);
        #warn __PACKAGE__.':'.__LINE__.$".Data::Dumper->Dump([\@args], ['args']);
        my $expr = '';
        if ($op->[0] eq 'BIN_OP') {
            $expr .= ' ( ';
            $expr .= $class->sub_expression($args[0], $compiler, $htc, %args);
            $expr .= ' ' . $op->[1] . ' ';
            $expr .= $class->sub_expression($args[1], $compiler, $htc, %args);
            $expr .= ' ) ';
        }
        #warn __PACKAGE__.':'.__LINE__.": $expr\n";
        return $expr;
    }
    elsif ($type eq 'VAR') {
        my $expr = $compiler->parse_var($htc,
            %args,
            var => $args[0],
        );
        #warn __PACKAGE__.':'.__LINE__.": VAR $expr\n";
        return $expr;
    }
    elsif ($type eq 'LITERAL') {
        #warn __PACKAGE__.':'.__LINE__.$".Data::Dumper->Dump([\@args], ['args']);
        my $expr = $args[0];
        return $expr;
    }
    elsif ($type eq 'LITERAL_STRING') {
        my $expr = $args[0] . $args[1] . $args[0];
        return $expr;
    }
    elsif ($type eq 'METHOD_CALL') {
        #warn __PACKAGE__.':'.__LINE__.$".Data::Dumper->Dump([\@args], ['args']);
        my ($var, $params) = @args[0,1];
        my $method_args = '';
        for my $i (0 .. $#$params) {
            $method_args .= $class->sub_expression($params->[$i], $compiler, $htc, %args) . ' , ';
        }
        my $expr = $compiler->parse_var($htc,
            %args,
            var => $var->[1],
            method_args => $method_args,
        );
    }
    elsif ($type eq 'FUNCTION_CALL') {
        my $name = shift @args;
        @args = @{ $args[0] || [] };
        my $expr = "$name( ";
        for my $i (0 .. $#args) {
            $expr .= $class->sub_expression($args[$i], $compiler, $htc, %args) . ' , ';
        }
        $expr .= ")";
        return $expr;
    }
}

1;

__END__

=pod

=head1 NAME

HTML::Template::Compiled::Expr - Expressions for HTC

=head1 DESCRIPTION

Works like L<HTML::Template::Expr>, with the additional possibility
to do method calls with parameters.

See the option C<use_expressions> in L<HTML::Template::Compiled/"OPTIONS">

=cut
