# $Id: 21_while.t,v 1.2 2006/07/05 19:00:55 tinita Exp $
use warnings;
use strict;
use lib qw(blib/lib t);
use Test::More tests => 2;
use_ok('HTML::Template::Compiled');
use HTC_Utils qw($cache $tdir &cdir);


{
    my $class = 'HTML::Template::Compiled::__Test';
    my $iterator = bless [undef,[23..25]], $class;
    my $next = sub {
        my ($self) = @_;
        my $index = $self->[0];
        my $array = $self->[1];
        return unless @$array;
        unless (defined $index) {
            $self->[0] = $index = 0;
        }
        elsif ($index < $#$array) {
            $self->[0] = ++$index;
        }
        else {
            $self->[0] = undef;
            return;
        }
        return $array->[$index];
    };
    {
        no strict 'refs';
        *{$class."::next"} = $next;
    }

    my $htc = HTML::Template::Compiled->new(
        filehandle => \*DATA,
        debug => 0,
    );
    #while (my $row = $iterator->next) {
        #print "row $row\n";
        #}
    $htc->param(iterator => $iterator);
    my $out = $htc->output;
    cmp_ok($out,"=~", qr{23.*24.*25.*23.*24.*25}s, "while");
    #print "out: $out\n";

}


__DATA__
<%with iterator%>
<%while next %>
    <%VAR NAME="_" %>
<%/while%>
<%while next alias=hiThere%>
    <%VAR NAME="hiThere" %>
<%/while%>
<%/with iterator%>

