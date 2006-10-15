package HTML::Template::Compiled::Parser;
# $Id: Parser.pm,v 1.43 2006/10/12 20:05:54 tinita Exp $
use Carp qw(croak carp confess);
use strict;
use warnings;
use base qw(Exporter);
use HTML::Template::Compiled::Token;
our $VERSION = 0.04;
my @vars;
BEGIN {
@vars = qw(
    $CASE_SENSITIVE_DEFAULT
    $NEW_CHECK
    $ENABLE_SUB
    $DEBUG_DEFAULT
    $SEARCHPATH
    %FILESTACK $DEFAULT_ESCAPE $DEFAULT_QUERY
    $UNTAINT $DEFAULT_TAGSTYLE
    $UNDEF
);
}
our @EXPORT_OK = @vars;
use vars @vars;

$NEW_CHECK              = 60 * 10; # 10 minutes default
$DEBUG_DEFAULT          = 0;
$CASE_SENSITIVE_DEFAULT = 1; # set to 0 for H::T compatibility
$ENABLE_SUB             = 0;
$SEARCHPATH             = 0;
$DEFAULT_ESCAPE         = 0;
$UNDEF                  = ''; # set for debugging
$UNTAINT                = 0;
$DEFAULT_QUERY          = 0;
$DEFAULT_TAGSTYLE       = [qw(classic comment asp)];

use constant NO_TAG      => 0;

use constant ATTR_TAGSTYLE => 0;
use constant ATTR_TAGNAMES => 1;

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


# under construction (sic!)
sub new {
    my $class = shift;
    my %args = @_;
    my $self = [];
    bless $self, $class;
    $self->init(%args);
    $self;
}

sub set_tagstyle { $_[0]->[ATTR_TAGSTYLE] = $_[1] }
sub get_tagstyle { $_[0]->[ATTR_TAGSTYLE] }

sub set_tagnames { $_[0]->[ATTR_TAGNAMES] = $_[1] }
sub get_tagnames { $_[0]->[ATTR_TAGNAMES] }
sub add_tagnames {
    my ($self, $hash) = @_;
    @{ $_[0]->[ATTR_TAGNAMES] }{keys %$hash} = values %$hash;
}


sub default_tags {
    return {
        classic => ['<TMPL_'      ,'>',     '</TMPL_',      '>',    ],
        comment => ['<!--\s*TMPL_','\s*-->','<!--\s*/TMPL_','\s*-->'],
        asp     => ['<%'          ,'%>',    '<%/',          '%>',   ],
        php     => ['<\?'         ,'\?>',    '<\?/',          '\?>',   ],
        tt      => ['\[%'         ,'%\]',   '\[%/',         '%\]'   ],
    };
}

my $default_validation = sub { exists $_[1]->{NAME} };
my %allowed_tagnames = (
    VAR         => [$default_validation, qw(NAME ESCAPE DEFAULT)],
    # just an alias for VAR
    '='         => [$default_validation, qw(NAME ESCAPE DEFAULT)],
    IF_DEFINED  => [$default_validation, qw(NAME)],
    IF          => [$default_validation, qw(NAME)],
    UNLESS      => [$default_validation, qw(NAME)],
    ELSIF       => [$default_validation, qw(NAME)],
    ELSE        => [undef, qw(NAME)],
    WITH        => [$default_validation, qw(NAME)],
    COMMENT     => [undef, qw(NAME)],
    VERBATIM    => [undef, qw(NAME)],
    NOPARSE     => [undef, qw(NAME)],
    LOOP        => [$default_validation, qw(NAME ALIAS)],
    WHILE       => [$default_validation, qw(NAME ALIAS)],
    SWITCH      => [$default_validation, qw(NAME)],
    CASE        => [undef, qw(NAME)],
    INCLUDE_VAR => [$default_validation, qw(NAME)],
    INCLUDE     => [$default_validation, qw(NAME)],
);


sub init {
    my ($self, %args) = @_;
    my $tagnames = $args{tagnames} || {};
    my $tagstyle = $self->_create_tagstyle($args{tagstyle});
    $self->[ATTR_TAGSTYLE] = $tagstyle;
    $self->[ATTR_TAGNAMES] = {%allowed_tagnames, %$tagnames};
}

sub _create_tagstyle {
    my ($self, $tagstyle_def) = @_;
    $tagstyle_def ||= [];
    my $tagstyle;
    my $named_styles = {
        map {
            ($_ => $self->default_tags->{$_})
        } @$DEFAULT_TAGSTYLE
    };
    for my $def (@$tagstyle_def) {
        if (ref $def eq 'ARRAY' && @$def == 4) {
            # we got user defined regexes
            push @$tagstyle, $def;
        }
        elsif (!ref $def) {
            # strings
            if ($def =~ m/^-(.*)/) {
                # deactivate style
                delete $named_styles->{"$1"};
            }
            elsif ($def =~ m/^\+?(.*)/) {
                # activate style
                $named_styles->{"$1"} = $self->default_tags->{"$1"};
            }
        }
    }
    push @$tagstyle, values %$named_styles;
    return $tagstyle;
}

sub find_start_of_tag {
    my ($self, %args) = @_;
    my $text = $args{text};
    my $re = $args{re};
    if ($$text =~ s/^($re)//) {
        my $open = $args{open};
        my $token = $args{token};
        my %open_close_map = %{$args{open_close_map}};
        my $open_or_close = $args{open_or_close};
        my $close_match = $args{close_match};
        # $open contains <TMPL_ or <% or </TMPL_...
        $$open = $1;
        $$token .= $1;
        # check which type of tag we got
        TYPES: for my $key (keys %open_close_map) {
            #print STDERR "try $key '$$open'\n";
            if ($$open =~ m/^$key$/i) {
                my $val = $open_close_map{$key};
                $$close_match = $val->[1];
                $$open_or_close = $val->[0];
                #print STDERR "=== tag type $key, searching for $close_match\n";
                last TYPES;
            }
        }
        #print STDERR "got start_close_re\n";
        return 1;
    }
    else {
        return;
    }
}

sub find_attributes {
    my ($self, %args) = @_;
    #warn Data::Dumper->Dump([\%args], ['args']);
    my $text = $args{text};
    my $allowed = $args{allowed_names};
    my $close_match = $args{close_match};
    my $attr = $args{attr};
    my $fname = $args{fname};
    my $line = $args{line};
    my $token = $args{token};
    my $open_or_close = $args{open_or_close};

    my $required_tags;
    my ($validate_sub, @allowed) = @$allowed;
    my $allowed_names = [ map {
        my $name = $_;
        $name =~ s/^!// and $required_tags->{$name}++;
        $name;
    } sort {
        length($b) <=> length($a)
    } @allowed ];
    my $found_attr = 0;
    ATTR: while (1) {
        last if $$text =~ m/^($close_match)/;
        my ($name, $val, $orig) = $self->find_attribute(
            $text, $close_match, $allowed_names
        );
        if (defined $name) {
            my $key = uc $name;
            if (exists $attr->{$key}) {
                $self->_error_wrong_tag_syntax(
                    $fname, $line, $$token, $orig.$$text
                );
            }
            $attr->{$key} = $val;
            $$token .= $orig;
        }
        last unless defined $name;
    }
    my $ok = $validate_sub ? $validate_sub->(undef, $attr) : 1;
    return 1 if $open_or_close == HTML::Template::Compiled::Token::CLOSING_TAG;
    return $ok;
}

{

    sub parse {
        my ($self, $fname, $text) = @_;
        my $tagnames = $self->get_tagnames;
        my $allowed_ident = "(?i:" . join("|", sort {
            length $b <=> length $a
        } keys %$tagnames) . ")";
        my $tagstyle = $self->get_tagstyle;
        # make (?i:IF_DEFINED|LOOP|IF|=|...) out of the list of identifiers
        my $start_close_re = '(?i:' . join("|", sort {
                length($b) <=> length($a)
            } map {
                $_->[0], $_->[2]
            } @$tagstyle) . ")";
        my @tags;
        my $token = "";
        my %open_close = map {
            (
                $_->[0] => [
                    HTML::Template::Compiled::Token::OPENING_TAG, $_->[1]
                ],
                $_->[2] => [
                    HTML::Template::Compiled::Token::CLOSING_TAG, $_->[3]
                ],
            ),
        } @$tagstyle;
        my $line = 1;
        my $stack = [T_END];
        my $comment_info;
        my $callbacks_found_text = [
            sub {
                my ($self, %args) = @_;
                ${$args{line}} += ${$args{token}} =~ tr/\n//;
                #print STDERR "we found text: '${$args{token}}'\n";
                push @{$args{tags}},
                HTML::Template::Compiled::Token::Text->new([
                    ${$args{token}}, ${$args{line}},
                    undef, undef, undef, undef, ${$args{fname}}
                ]);
                ${$args{token}} = "";
            }
        ];
        my $callback_found_tag = [
        sub {
            my ($self, %args) = @_;
            #print STDERR "####found tag ${$args{name}}\n";
            ${$args{line}} += ${$args{token}} =~ tr/\n//;
            my $class = 'HTML::Template::Compiled::Token::' .
                (${$args{open_or_close}} == HTML::Template::Compiled::Token::OPENING_TAG
                    ? 'open'
                    : 'close');

            push @{$args{tags}}, $class->new([
                ${$args{token}}, ${$args{line}},
                ${$args{open}}, ${$args{name}}, $args{attr}, ${$args{close}},
                ${$args{fname}},
            ]);
            $self->checkstack(
                ${$args{fname}}, ${$args{line}}, $args{stack},
                ${$args{name}}, ${$args{open_or_close}}
            );
            ${$args{token}} = "";
        }
        ];
        my $ignore_tag = sub {
            my ( $p, %args ) = @_;
            ${ $args{token} } = "";
        };
        my $encode_tag = sub {
            my ( $p, %args ) = @_;
            my $token = ${ $args{token} };
            ${ $args{token} } = "";
            HTML::Entities::encode_entities($token);
            $callbacks_found_text->[0]->($self, %args, token => \$token);
        };

        my $callback = sub {
            my ( $p, %args ) = @_;
            my $name = ${ $args{name} };
            #print STDERR "callback found tag $name\n";
            my $open_or_close = ${ $args{open_or_close} };
            if ( $name eq 'COMMENT' ) {
                #print STDERR "======== $args{name} $args{open_or_close}\n";
                if ( $open_or_close == HTML::Template::Compiled::Token::OPENING_TAG ) {
                    ++$comment_info->{$name} == 1
                        and push @$callbacks_found_text, $ignore_tag;
                } ## end if ( $open_or_close ==...
                elsif ( $open_or_close == HTML::Template::Compiled::Token::CLOSING_TAG ) {
                    --$comment_info->{$name} == 0
                        and pop @$callbacks_found_text;
                }
                ${ $args{token} } = "";
                #print STDERR "$open_or_close $comment_info->{ $name }\n";
            } ## end if ( $name eq 'COMMENT')
            elsif ( $comment_info->{COMMENT} ) {
                ${ $args{token} } = "";
            }
            elsif ($name eq 'NOPARSE') {
                if ( $open_or_close == HTML::Template::Compiled::Token::OPENING_TAG ) {
                    if (++$comment_info->{$name} == 1) {
                        ${ $args{token} } = "";
                    }
                    else {
                        $callbacks_found_text->[0]->(@_);
                        #${ $args{token} } = "";
                    }
                }
                elsif ( $open_or_close == HTML::Template::Compiled::Token::CLOSING_TAG ) {
                    if (--$comment_info->{$name} == 0) {
                        ${ $args{token} } = "";
                    }
                    else {
                        $callbacks_found_text->[0]->(@_);
                    }
                }
            }
            elsif ( $comment_info->{NOPARSE} ) {
                $callbacks_found_text->[0]->(@_);
            }
            elsif ($name eq 'VERBATIM') {
                if ( $open_or_close == HTML::Template::Compiled::Token::OPENING_TAG ) {
                    if (++$comment_info->{$name} == 1) {
                        ${ $args{token} } = "";
                    }
                    else {
                        $encode_tag->(@_);
                    }
                }
                elsif ( $open_or_close == HTML::Template::Compiled::Token::CLOSING_TAG ) {
                    if (--$comment_info->{$name} == 0) {
                        ${ $args{token} } = "";
                    }
                    else {
                        $encode_tag->(@_);
                    }
                }
            }
            elsif ( $comment_info->{VERBATIM} ) {
                $encode_tag->(@_);
            }
            else {
                $callback_found_tag->[-2]->(@_);
            }
        };
        push @$callback_found_tag, $callback;

        while (length $text) {
            #warn Data::Dumper->Dump([\@tags], ['tags']);
            #print STDERR "TEXT: $text ($start_close_re)\n";
            #print STDERR "TOKEN: '$token'\n";
            my ($open, $close, $ident, $var, $expr, $close_match,
                $open_or_close, $found_tag, $attr);
            $attr = {};
            MATCH_TAGS: {
                if ($self->find_start_of_tag(
                        text => \$text,
                        re => qr{$start_close_re},
                        open => \$open,
                        token => \$token,
                        open_or_close => \$open_or_close,
                        open_close_map => \%open_close,
                        close_match => \$close_match,
                    )) {
                }
                else { last MATCH_TAGS }
                # at this point we have a start of a tag. everything
                # that does not look like correct tag content generates
                # a die!
                if ($text =~ s/^(($allowed_ident)\s*)//) {
                    $ident = uc $2;
                    $token .= $1;
                    if ($ident eq '=') { $ident = 'VAR' }
                }
                else {
                    $self->_error_wrong_tag_syntax(
                        $fname, $line, $token, $text
                    );
                    last MATCH_TAGS;
                }
                #print STDERR "got ident $ident ('$text')\n";
                if ($self->find_attributes(
                        attr => $attr,
                        text => \$text,
                        allowed_names => $tagnames->{$ident},
                        close_match => $close_match,
                        fname => $fname,
                        line => $line,
                        token => \$token,
                        open_or_close => $open_or_close,
                    )) {
                    #warn Data::Dumper->Dump([\$attr], ['attr']);
                }
                else {
                    $self->_error_wrong_tag_syntax(
                        $fname, $line, $token, $text
                    );
                    last MATCH_TAGS;
                }
                if ($text =~ s/^($close_match)//) {
                    $close = $1;
                    $token .= $1;
                }
                else {
                    $self->_error_wrong_tag_syntax(
                        $fname, $line, $token
                    );
                    last MATCH_TAGS;
                }
                $found_tag = 1;
            }
            if ($found_tag) {
                #print STDERR "found tag $ident\n";
                #my $test = $callback_found_tag->[-1];
                #print STDERR "(found_tags: @$callback_found_tag) $test\n";
                ( $callback_found_tag->[-1] || sub { } )->(
                    $self,
                    tags => \@tags,
                    stack => $stack,
                    token         => \$token,
                    open_or_close => \$open_or_close,
                    line          => \$line,
                    open          => \$open,
                    name          => \$ident,
                    attr          => $attr,
                    close         => \$close,
                    fname         => \$fname,
                );
                #print STDERR "===== ($open, $line, $ident, $close)\n";
                #warn Data::Dumper->Dump([\$attr], ['attr']);
                #warn Data::Dumper->Dump([\@tags], ['tags']);
            }
            elsif ($text =~ s/^(.+?)(?=($start_close_re|\Z))//s) {
                ($callbacks_found_text->[-1] || sub {} )->(
                    $self,
                    token => \"$token$1",
                    line => \$line,
                    tags => \@tags,
                    fname => \$fname,
                );
                #print "got no tag: '$token'\n";
            }

        }
        $self->checkstack($fname, $line, $stack, T_END, HTML::Template::Compiled::Token::CLOSING_TAG);
        return @tags;
    }
}

sub _error_wrong_tag_syntax {
    my ($self, $file, $line, $token, $text) = @_;
    my ($substr) = $text =~ m/^(.{0,10})/s;
    my $class = ref $self || $self;
    croak "$class : Syntax error in <TMPL_*> tag at $file : $line near '$token$substr...'";
}

sub find_attribute {
    my ($self, $text, $until, $allowed_names) = @_;
    my ($name, $var, $orig);
    my $re = join '|', @$allowed_names;
    if ($$text =~ s/^(\s*($re)=)//i) {
        $name = $2;
        $orig .= $1;
    }
    #print STDERR "match '$$text' (?=$until|\\s)\n";
    if ($$text =~ s{^ (\s* " ([^"]+) " \s*) }{}x) {
        #print STDERR qq{matched "$2"\n};
        $var = $2;
        $orig .= $1;
    }
    elsif ($$text =~ s{^ (\s* ' ([^']+) ' \s*) }{}x) {
        #print STDERR qq{matched '$2'\n};
        $var = $2;
        $orig .= $1;
    }
    elsif ($$text =~ s{^ (\s* (\S+?) \s*) (?=$until | \s) }{}x) {
        #print STDERR qq{matched <$2>\n};
        $var = $2;
        $orig .= $1;
    }
    else { return }
    unless (defined $name) {
        $name = "NAME";
    }
    return ($name, $var, $orig);
}

{
    my @map;
    $map[HTML::Template::Compiled::Token::OPENING_TAG] = {
        ELSE       => [ T_IF, T_UNLESS, T_ELSIF, T_IF_DEFINED ],
        T_CASE()   => [T_SWITCH],
    };
    $map[HTML::Template::Compiled::Token::CLOSING_TAG] = {
        IF         => [ T_IF, T_UNLESS, T_ELSE ],
        UNLESS     => [T_UNLESS, T_ELSE, T_IF_DEFINED],
        ELSIF      => [ T_IF, T_UNLESS, T_IF_DEFINED ],
        LOOP       => [T_LOOP],
        WHILE      => [T_WHILE],
        WITH       => [T_WITH],
        T_SWITCH() => [T_SWITCH],
        T_END()    => [T_END],
    };

    sub validate_stack {
        my ( $self, $fname, $line, $stack, $check, $open_or_close ) = @_;
        if (exists $map[$open_or_close]->{$check}) {
            my @allowed = @{ $map[$open_or_close]->{$check} };
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

    sub checkstack {
        my ( $self, $fname, $line, $stack, $check, $open_or_close ) = @_;
        my $ok = $self->validate_stack($fname, $line, $stack, $check, $open_or_close);
        if ($open_or_close == HTML::Template::Compiled::Token::OPENING_TAG) {
            if (
                grep { $check eq $_ } (
                    T_WITH, T_LOOP, T_WHILE, T_IF, T_UNLESS, T_SWITCH, T_IF_DEFINED
                )
                ) {
                push @$stack, $check;
            }
            elsif ($check eq T_ELSE) {
                pop @$stack;
                push @$stack, T_ELSE;
            }
        }
        elsif ($open_or_close == HTML::Template::Compiled::Token::CLOSING_TAG) {
            if (grep { $check eq $_ } (
                    T_IF, T_UNLESS, T_WITH, T_LOOP, T_WHILE, T_SWITCH
                )) {
                pop @$stack;
            }
        }
        return $ok;
    }

}

{
    my $default_parser = __PACKAGE__->new;
    sub default { return bless [@$default_parser], __PACKAGE__ }
}

1;

__END__

=pod

=head1 NAME

HTML::Template::Compiled::Parser - Parser module for HTML::Template::Compiled

=head1 SYNOPSIS

This module is used internally by HTML::Template::Compiled. The API is
not fixed (yet), so this is just for understanding at the moment.

    my $parser = HTML::Template::Compiled::Parser->new(
        tagstyle => [
            # -name deactivates style
            # +name activates style
            qw(-classic -comment +asp +php),
            # define own regexes
            # e.g. for tags like
            # {{if foo}}{{var bar}}{{/if foo}}
            [
            qr({{), start of opening tag
            qr(}}), # end of opening tag
            qr({{/), # start of closing tag
            qr(}}), # end of closing tag
            ],
        ],
    );

=head1 AUTHOR

Tina Mueller


=cut


