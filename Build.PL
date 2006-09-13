use strict;
use warnings;
use Module::Build;

my $build = Module::Build->new(
    create_makefile_pl => 'traditional',
    license            => 'perl',
    module_name        => 'HTML::Template::Compiled',
    requires => {
        'Test::More'     => 0,
        'File::Spec'     => 0,
        'File::Basename' => 0,
        Carp             => 0,
    },
    reccomends         => {},
    create_readme      => 0,
    sign               => 0,
);
$build->create_build_script;
