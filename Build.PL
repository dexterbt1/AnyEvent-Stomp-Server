use strict;
use warnings;
use Module::Build;

my $builder = Module::Build->new(
    module_name         => 'AnyEvent::Stomp::Broker',
    license             => 'perl',
    dist_author         => 'Dexter Tad-y <dtady@cpan.org>',
    dist_version_from   => 'lib/AnyEvent/Stomp/Broker.pm',
    build_requires => {
        'Test::More'            => 0,
    },
    requires => {
        'Net::Stomp::Frame'     => 0,
        'Sub::Exporter'         => 0,
        'AnyEvent'              => 5.31,
        'AnyEvent::STOMP'       => 0.5,
        'Object::Event'         => '<= 1.21',
    },
    add_to_cleanup      => [ 'AnyEvent-Stomp-Broker-*' ],
    create_makefile_pl => 'traditional',
);

$builder->create_build_script();
