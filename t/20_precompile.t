# $Id: 20_precompile.t,v 1.1 2006/04/24 20:38:11 tinita Exp $
use warnings;
use strict;
use lib qw(blib/lib t);
use Test::More tests => 4;
use_ok('HTML::Template::Compiled');
use HTC_Utils qw($cache $tdir &cdir);


HTML::Template::Compiled->clear_filecache('t/cache');
{
    my $pre = 'precompiled1.tmpl';
    my $scalar = <<'EOM';
Precompiled scalarref!
EOM
    my $templates = HTML::Template::Compiled->precompile(
        path     => $tdir,
        cache_dir => $cache,
        filenames => [$pre, \$scalar],
    );
    #warn Data::Dumper->Dump([\$templates], ['templates']);
    my $out = $templates->[0]->output;
    #print "out: '$out'\n";
    my $out2 = $templates->[1]->output;
    #print "out2: '$out2'\n";
    my $exp = do {
        open my $fh, '<', File::Spec->catfile($tdir, $pre) or die $!;
        local $/;
        <$fh>;
    };
    tr/\r\n//d for $exp, $out, $out2, $scalar;
    cmp_ok(scalar @$templates, "==", 2, "precompile count");
    cmp_ok($out, "eq", $exp, "precompiled output");
    cmp_ok($out2, "eq", $scalar, "precompiled scalarref");
    #print `ls t/cache/`;

}
HTML::Template::Compiled->clear_filecache('t/cache');



