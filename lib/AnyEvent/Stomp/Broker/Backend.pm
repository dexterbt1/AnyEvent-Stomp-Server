package AnyEvent::Stomp::Broker::Backend;
use Moose::Role;

requires 'send';                        # ($destination, $headers, $body_ref, $success_cb, $failure_cb)
    # success_cb( )
    # failure_cb( $reason )

requires 'subscribe';                   # ($subscription, $success_cb, $failure_cb)
    # success_cb( $subscription )
    # failure_cb( $subscription, $reason )

1;

__END__
