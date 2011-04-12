package AnyEvent::Stomp::Broker::Backend;
use Moose::Role;

requires 'send';                        # ($frame)
requires 'subscribe';                   # ($frame, $subscription_id)

1;

__END__
