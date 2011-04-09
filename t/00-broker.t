use strict;
use Test::More qw/no_plan/;

BEGIN {
    use_ok 'AnyEvent::Stomp::Broker';
    use_ok 'Net::Stomp';
    use_ok 'YAML';
}

require 't/TestBroker.pm';
my $PORT = 16163;

my $pid = TestBroker->fork_and_run( listen_port => $PORT,);

eval {
    my $stomp;
    my $connected;

    # basic connect
    $stomp = Net::Stomp->new( { hostname => 'localhost', port => $PORT } );
    $connected = $stomp->connect( { login => "username", passcode => "password" } );
    diag Dump($connected);
    is $connected->{headers}->{version}, '1.0';
    ok exists $connected->{headers}->{'session-id'};
    $stomp->disconnect;

    # protocol negotiation success
    $stomp = Net::Stomp->new( { hostname => 'localhost', port => $PORT } );
    $connected = $stomp->connect( { 'accept-version' => '1.1', login => "username", passcode => "password" } );
    diag Dump($connected);
    is $connected->{headers}->{version}, '1.1';
    ok exists $connected->{headers}->{'session-id'};
    ok exists $connected->{headers}->{server};
    $stomp->disconnect;

    # protocol negotiation unsupported
    $stomp = Net::Stomp->new( { hostname => 'localhost', port => $PORT } );
    $connected = $stomp->connect( { 'accept-version' => '12345.67890', login => "username", passcode => "password" } );
    diag Dump($connected);
    is $connected->{command}, 'ERROR';
    $stomp->disconnect;


    # TODO: authentication
    # TODO: virtual hosting 
    
};
my $run_error = $@;
kill 'KILL', $pid;
if ($run_error) { die $@; }
my $reaped = waitpid($pid, 0);
#is $?, 0;
#is $reaped, $pid;

ok 1;

__END__
