package AnyEvent::Stomp::Server::Session::Subscription;
use strict;
use Mouse;
use AnyEvent::Stomp::Server::Constants '-all';

has 'id'            => (is => 'rw', isa => 'Str', required => 1);
has 'session'       => (is => 'rw', does => 'AnyEvent::Stomp::Server::Role::Session', weak_ref => 1, required => 1);
has 'destination'   => (is => 'rw', isa => 'Str', required => 1);
has 'ack'           => (is => 'rw', isa => 'Int', lazy => 1, default => sub { STOMP_ACK_AUTO });


sub DEMOLISH {
}


__PACKAGE__->meta->make_immutable;

1;

__END__
