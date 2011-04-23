use strict;
use warnings;
use Module::Build;

my $builder = Module::Build->new(
    module_name         => 'AnyEvent::Stomp::Server',
    license             => 'perl',
    dist_author         => 'Dexter Tad-y <dtady@cpan.org>',
    dist_version_from   => 'lib/AnyEvent/Stomp/Server.pm',
    build_requires => {
        'Test::More'            => 0,
    },
    requires => {
        'Object::Event'         => '1.21',
        'Sub::Exporter'         => 0,
        'AnyEvent'              => '5.31',
    },
    add_to_cleanup      => [ 'AnyEvent-Stomp-Broker-*' ],
    create_makefile_pl => 'traditional',
);

$builder->create_build_script();
