package AnyEvent::Stomp::Broker::Role::Backend;
use Moose::Role;

requires 'send';                        # ($destination, $headers, $body_ref, $success_cb, $failure_cb)
    # success_cb( )
    # failure_cb( $reason )

requires 'subscribe';                   # ($subscription, $success_cb, $failure_cb)
    # success_cb( $subscription )
    # failure_cb( $reason, $subscription )

1;

__END__
