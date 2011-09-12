package AnyEvent::Stomp::Server::Role::Session;
use Any::Moose 'Role';

has 'session_id'            => ( is => 'rw', isa => 'Any' );

requires 'send_client_message'; # $obj->send_client_message( $subcription, $msg_id, $dest, $body_ref, $headers );

1;

__END__

