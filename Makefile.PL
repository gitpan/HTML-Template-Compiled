use ExtUtils::MakeMaker;
# $Id: Makefile.PL,v 1.3 2005/11/23 20:16:15 tinita Exp $
# See lib/ExtUtils/MakeMaker.pm for details of how to influence
# the contents of the Makefile that is written.
WriteMakefile(
    NAME              => 'HTML::Template::Compiled',
    VERSION_FROM      => 'lib/HTML/Template/Compiled.pm', # finds $VERSION
    PREREQ_PM         => {
        'Test::More' => 0,
        'File::Spec' => 0,
        'File::Basename' => 0,
		Carp => 0,
    },
    ($] >= 5.005
        ?     ## Add these new keywords supported since 5.005
        (ABSTRACT_FROM  => 'lib/HTML/Template/Compiled.pm',
        AUTHOR         => 'Tina Mueller (tinita~at~cpan . org)')
    : ()),
);
