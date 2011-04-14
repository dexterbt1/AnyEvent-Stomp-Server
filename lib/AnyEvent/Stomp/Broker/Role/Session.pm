package AnyEvent::Stomp::Broker::Role::Session;
use Moose::Role;

has 'session_id'            => ( is => 'rw', isa => 'Any' );

requires 'send_client_message'; # ( 

1;

__END__

