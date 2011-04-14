package AnyEvent::Stomp::Broker::Role::Backend;
use Moose::Role;

requires 'send';                        # $be->send($destination, $headers, $body_ref, $success_cb, $failure_cb)
    # success_cb( )
    # failure_cb( $reason )

requires 'subscribe';                   # $be->subscribe($subscription, $success_cb, $failure_cb)
    # success_cb( $subscription )
    # failure_cb( $reason, $subscription )

requires 'on_session_disconnect';       # $be->session_disconnect($session)

1;

__END__
