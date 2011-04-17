package AnyEvent::Stomp::Broker::Role::Backend;
use Moose::Role;

requires 'connect';                     # $be->connect($session, $success_cb, $failure_cb)
    # success_cb( $session )
    # failure_cb( $reason, $session )

requires 'send';                        # $be->send($session, $destination, $headers, $body_ref, $success_cb, $failure_cb)
    # success_cb( )
    # failure_cb( $reason )

requires 'subscribe';                   # $be->subscribe($session, $subscription, $success_cb, $failure_cb)
    # success_cb( $subscription )
    # failure_cb( $reason, $subscription )

requires 'ack';                         # $be->ack($session, $msg_id, $success_cb, $failure_cb)
    # success_cb( $session, $msg_id )
    # failure_cb( $reason, $session, $msg_id )

requires 'disconnect';                  # $be->disconnect($session)



1;

__END__
