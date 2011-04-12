package AnyEvent::Stomp::Broker::Backend;
use Moose::Role;

requires 'send';
requires 'subscribe';

1;

__END__
