use strict;
use warnings;
use ExtUtils::MakeMaker;

WriteMakefile(
    NAME                => 'Test::MonitorSites',
    AUTHOR              => 'Hugh Esco <hesco@greens.org>',
    VERSION_FROM        => 'lib/Test/MonitorSites.pm',
    ABSTRACT_FROM       => 'lib/Test/MonitorSites.pm',
    PL_FILES            => {},
    PREREQ_PM => {
        'Cwd'                   => 0,
        'Carp'                  => 0,
        'Data::Dumper'          => 0,
        'Test::More'            => 0,
        'Test::Pod'             => 1.14,
        'Test::Pod::Coverage'   => 1.04,
        'Test::Builder'         => 0,
        'Mail::Mailer'          => 0,
        'Config::Simple'        => 0,
        'WWW::Mechanize'        => 0,
        'Test::WWW::Mechanize'  => 0,
        'Test::HTML::Tidy'      => 0,
        'HTTP::Request::Common' => 0,
        'Test::Builder::Tester' => 0,
    },
    dist                => { COMPRESS => 'gzip -9f', SUFFIX => 'gz', },
    clean               => { FILES => 'Test-MonitorSites-*' },
);
