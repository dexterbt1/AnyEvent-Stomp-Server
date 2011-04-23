package AnyEvent::Stomp::Server;
use strict;

our $VERSION = '0.10';

use Mouse;
use AnyEvent;
use AnyEvent::Socket;
use AnyEvent::Stomp::Server::Session;

has 'listen_host' 
    => ( is => 'rw', isa => 'Str', lazy => 1, default => sub { '0.0.0.0' }, );
has 'listen_port' 
    => ( is => 'rw', isa => 'Int', required => 1 );
has 'session_class' 
    => ( is => 'rw', isa => 'Str', lazy => 1, default => 'AnyEvent::Stomp::Server::Session' );
has 'backend'
    => ( is => 'rw', does => 'AnyEvent::Stomp::Server::Role::Backend', required => 1 );

sub BUILD {
    my ($self) = @_;
    tcp_server( 
        $self->listen_host, 
        $self->listen_port, 
        sub { # accept callback
            my ($fh, $host, $port) = @_;
            my $session = $self->session_class->new(
                parent_broker => $self,
                socket  => $fh,
                host    => $host,
                port    => $port
            );
        },
    );
}


__PACKAGE__->meta->make_immutable;

1;


__END__

=head1 NAME

AnyEvent::Stomp::Server - a server framework for building Stomp Messaging Servers

=cut
