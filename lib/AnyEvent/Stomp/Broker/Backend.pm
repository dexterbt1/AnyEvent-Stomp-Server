package AnyEvent::Stomp::Broker::Backend;
use Moose::Role;

requires 'send';                        # ($session, $send_success_cb)
requires 'subscribe';                   # ($subscription, $success_cb, $failure_cb)

1;

__END__
