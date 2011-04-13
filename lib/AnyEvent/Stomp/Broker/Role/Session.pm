package AnyEvent::Stomp::Broker::Role::Session;
use Moose::Role;

has 'session_id'            => ( is => 'rw', isa => 'Any' );

1;

__END__

