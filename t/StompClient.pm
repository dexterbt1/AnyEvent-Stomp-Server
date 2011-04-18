package StompClient;
use strict;

BEGIN {
    # aliased to AnyEvent::STOMP
    require 't/ae-stomp/lib/AnyEvent/STOMP.pm';
    *StompClient:: = *AnyEvent::STOMP::;
    $INC{'StompClient.pm'}++;
}

1;

__END__
