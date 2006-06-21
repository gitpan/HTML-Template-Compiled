package HTML::Template::Compiled::Parser;
# $Id: Parser.pm,v 1.15 2006/06/15 20:19:37 tinita Exp $
use Carp qw(croak carp confess);
use strict;
use warnings;
use base qw(Exporter);
our $VERSION = 0.01;
my @vars;
BEGIN {
@vars = qw(
    $CASE_SENSITIVE_DEFAULT
    $NEW_CHECK
    $ENABLE_SUB
    $DEBUG_DEFAULT
    $SEARCHPATH
    %FILESTACK %SUBSTACK $DEFAULT_ESCAPE $DEFAULT_QUERY
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
$SEARCHPATH             = 1;
$DEFAULT_ESCAPE         = 0;
$UNDEF                  = ''; # set for debugging
$UNTAINT                = 0;
$DEFAULT_QUERY          = 0;
$DEFAULT_TAGSTYLE       = [qw(classic comment asp)];

use constant NO_TAG      => 0;
use constant OPENING_TAG => 1;
use constant CLOSING_TAG => 2;

use constant ATTR_TAGSTYLE => 0;

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

my $supported_tags = {
    classic => ['<TMPL_'      ,'>',     '</TMPL_',      '>',    ],
    comment => ['<!--\s*TMPL_','\s*-->','<!--\s*/TMPL_','\s*-->'],
    asp     => ['<%'          ,'%>',    '<%/',          '%>',   ],
    php     => ['<\?'         ,'%>',    '<%/',          '%>',   ],
    tt      => ['\[%'         ,'%\]',   '\[%/',         '%\]'   ],
};


sub init {
    my ($self, %args) = @_;
    my $tagstyle_def = $args{tagstyle} || [];
    my $tagstyle;
    my $named_styles = {
        map {
            ($_ => $supported_tags->{$_})
        } @$DEFAULT_TAGSTYLE
    };
    for my $def (@$tagstyle_def) {
        if (ref $def eq 'ARRAY' && @$def == 4) {
            # we got user defined regexes
            push @$tagstyle, $def;
        }
        elsif (!ref $def) {
            # strings
            if ($def =~ s/^-//) {
                # deactivate style
                delete $named_styles->{$def};
            }
            elsif ($def =~ s/^\+?//) {
                # activate style
                $named_styles->{$def} = $supported_tags->{$def};
            }
        }
    }
    push @$tagstyle, values %$named_styles;
    $self->[ATTR_TAGSTYLE] = $tagstyle;
}

{
    my %allowed_ident = (
        VAR => [qw(NAME ESCAPE DEFAULT)],
        '=' => [qw(NAME ESCAPE DEFAULT)], # just an alias for VAR
        IF_DEFINED => [qw(NAME)],
        'IF DEFINED' => [qw(NAME)], # deprecated
        IF => [qw(NAME)],
        UNLESS => [qw(NAME)],
        ELSIF => [qw(NAME)],
        ELSE => [qw(NAME)],
        WITH => [qw(NAME)],
        COMMENT => [qw(NAME)],
        VERBATIM => [qw(NAME)],
        NOPARSE => [qw(NAME)],
        LOOP_CONTEXT => [qw(NAME)],
        LOOP => [qw(NAME ALIAS)],
        WHILE => [qw(NAME)],
        SWITCH => [qw(NAME)],
        CASE => [qw(NAME)],
        INCLUDE_VAR => [qw(NAME)],
        INCLUDE => [qw(NAME)],
    );

    # make (?i:IF_DEFINED|LOOP|IF|=|...) out of the list of identifiers
    my $allowed_ident = "(?i:" . join("|", sort {
        length $b <=> length $a
    } keys %allowed_ident) . ")";
    sub tags {
        my ($self, $text) = @_;
        my $tagstyle = $self->get_tagstyle;
        my $start_close_re = '(?i:' . join("|", sort {
                length($b) <=> length($a)
            } map {
                $_->[0], $_->[2]
            } @$tagstyle) . ")";
        my @tags;
        my $token = "";
        my %open_close = map {
            (
                $_->[0] => [OPENING_TAG, $_->[1]],
                $_->[2] => [CLOSING_TAG, $_->[3]],
            ),
        } @$tagstyle;
        my $line = 1;
        while (length $text) {
            #warn Data::Dumper->Dump([\@tags], ['tags']);
            #print STDERR "TEXT: $text ($start_close_re)\n";
            #print STDERR "TOKEN: '$token'\n";
            my ($open, $close, $ident, $var, $expr, $close_match,
                $open_or_close, $found_tag, $attr);
            MATCH_TAGS: {
                if ($text =~ s/^($start_close_re)//) {
                    $open = $1;
                    $token .= $1;
                    # check which type of tag we got
                    TYPES: for my $key (keys %open_close) {
                        #print STDERR "try $key '$open'\n";
                        if ($open =~ m/^$key$/i) {
                            my $val = $open_close{$key};
                            $close_match = $val->[1];
                            $open_or_close = $val->[0];
                            #print STDERR "=== tag type $key, searching for $close_match\n";
                            last TYPES;
                        }
                    }
                    #print STDERR "got start_close_re\n";
                }
                else { last MATCH_TAGS }
                if ($text =~ s/^(($allowed_ident)\s*)//) {
                    $ident = uc $2;
                    $token .= $1;
                }
                else { last MATCH_TAGS }
                #print STDERR "got ident $ident ('$text')\n";
                my $found_attr = 0;
                ATTR: while (1) {
                    last if $text =~ m/^($close_match)/;
                    my ($name, $val, $orig) = find_attr(\$text, $close_match);
                    if (defined $name) {
                        $attr->{uc $name} = $val;
                        $token .= $orig;
                        #print STDERR "$name=$val\n";
                        $found_attr++;
                    }
                    last unless defined $name;
                }
                #warn Data::Dumper->Dump([\$attr], ['attr']);
                unless ($found_attr) {
                    last MATCH_TAGS if ($open_or_close == OPENING_TAG
                            and $ident !~ m/^(case|else|loop_context)$/i)
                }
                if ($text =~ s/^($close_match)//) {
                    $close = $1;
                    $token .= $1;
                }
                else { last MATCH_TAGS }
                $found_tag = 1;
            }
            if ($found_tag) {
                #print STDERR "===== ($open, $line, $ident, $close)\n";
                $line += $token =~ tr/\n//;
                if ($ident eq '=') { $ident = 'VAR' }
                push @tags, [$token, $open_or_close, $line, $open, $ident, $attr, $close];
                $token = "";
                #warn Data::Dumper->Dump([\$attr], ['attr']);
                #warn Data::Dumper->Dump([\@tags], ['tags']);
            }
            else {
                #print "got no tag: '$token'\n";
                if ($text =~ s/^(.+?)(?=($start_close_re|\Z))//s) {
                    $token .= $1;
                    $line += $token =~ tr/\n//;
                    push @tags, [$token, NO_TAG, $line];
                    $token = "";
                }
            }

        }
        return @tags;
    }
}
sub find_attr {
    my ($text, $until) = @_;
    my ($name, $var, $orig);
    if ($$text =~ s/^(\s*(NAME|ESCAPE|DEFAULT|EXPR|ALIAS)=)//i) {
        $name = $2;
        $orig .= $1;
    }
    #print STDERR "match '$$text' (?=$until|\\s)\n";
    if ($$text =~ s/^(\s*"([^"]+)"\s*)//) {
        #print STDERR qq{matched "$2"\n};
        $var = $2;
        $orig .= $1;
    }
    elsif ($$text =~ s/^(\s*'([^']+)'\s*)//) {
        #print STDERR qq{matched '$2'\n};
        $var = $2;
        $orig .= $1;
    }
    elsif ($$text =~ s/^(\s*(\S+?)\s*)(?=$until|\s)//) {
        #print STDERR qq{matched <$2>\n};
        $var = $2;
        $orig .= $1;
    }
    else { return }
    $name = "NAME" unless defined $name;
    return ($name, $var, $orig);
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


