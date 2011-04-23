package AnyEvent::Stomp::Server::Constants;
use strict;
use Sub::Exporter -setup => {
    exports => [
        qw/
        STOMP_ACK_AUTO
        STOMP_ACK_CLIENT
        STOMP_ACK_INDIVIDUAL
        /
    ],
};

sub STOMP_ACK_AUTO          { 0 }
sub STOMP_ACK_CLIENT        { 1 }
sub STOMP_ACK_INDIVIDUAL    { 2 }

1;

__END__
