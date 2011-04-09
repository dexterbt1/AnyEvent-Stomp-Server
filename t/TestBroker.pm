package TestBroker;
use strict;
use AnyEvent::Stomp::Broker;

sub fork_and_run {
    my $class = shift;
    my $pid = fork;
    if ($pid == 0) {
        $class->run(@_);
        exit(0);
    }
    else {
        sleep 1; # TODO: we probably need the child to signal/communicate w/ the parent when it is ready to return
        return $pid;
    }
}


sub run {
    my ($class, %opts) = @_;
    AnyEvent::Stomp::Broker->new( %opts );
    AnyEvent->condvar->recv;
}

1;
