package AnyEvent::Stomp::Broker::Protocol::Stomp1_1;
use strict;
use Moose;
extends 'AnyEvent::Stomp::Broker::Protocol::Stomp1_0';

sub protocol_version {
    '1.1'
}

1;

__END__

