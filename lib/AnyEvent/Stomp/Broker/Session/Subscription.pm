package AnyEvent::Stomp::Broker::Session::Subscription;
use strict;
use Moose;
use AnyEvent::Stomp::Broker::Constants '-all';

has 'id'            => (is => 'rw', isa => 'Str', required => 1);
has 'session'       => (is => 'rw', does => 'AnyEvent::Stomp::Broker::Role::Session', weak_ref => 1, required => 1);
has 'destination'   => (is => 'rw', isa => 'Str', required => 1);
has 'ack'           => (is => 'rw', isa => 'Int', lazy => 1, default => sub { STOMP_ACK_AUTO });


sub DEMOLISH {
}


__PACKAGE__->meta->make_immutable;

1;

__END__
