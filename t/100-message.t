use strict;
use Test::More qw/no_plan/;

BEGIN {
    use_ok 'AnyEvent::Stomp::Broker';
    use_ok 'AnyEvent::Stomp::Broker::Constants', '-all';
    use_ok 'AnyEvent::STOMP';
    use_ok 'YAML';
    require 't/MockBackend.pm';
}

my $PORT = 16163;

my $backend = MockBackend->new;
my $server = AnyEvent::Stomp::Broker->new( listen_port => $PORT, backend => $backend ); 
$AnyEvent::Stomp::Broker::Session::DEBUG = 1;

my $client;

{
    pass "v1.0 subscribe to foo then disconnect";
    # connect
    my $connected = AE::cv;
    my $subscribed = AE::cv;
    $backend->subscribe_obs(sub {
        my ($be, $sub, $sub_success_cb, $sub_fail_cb) = @_;
        $subscribed->send(1);
        return 1;
    });
    $client = AnyEvent::STOMP->connect( 'localhost', $PORT, 0, 'foo', undef );
    $client->reg_cb( connect_error => sub { diag $_[1]; $connected->send(0) } );
    my $io_error = $client->reg_cb( io_error => sub { $connected->send(0); } );
    $client->reg_cb( CONNECTED => sub { $connected->send(1); });
    ok $connected->recv;
    ok $subscribed->recv;
    my $disconnected = AE::cv;
    $client->unreg_cb( $io_error );
    $backend->disconnect_obs(sub {
        my ($be, $sess) = @_;
        $disconnected->send(1);
        return 1;
    });
    $client->{handle}->destroy;
    undef $client; # disconnect
    ok $disconnected->recv;
    
}

{
    # note, this is the 2nd test, the backend previously got a subscription to foo, but the client disconnected
    pass "v1.0 subscribe to foo, then simulate a MESSAGE";
    # connect
    my $QUEUE = 'foo';
    my $connected = AE::cv;
    my $subscribed = AE::cv;
    $backend->subscribe_obs(sub {
        my ($be, $sub, $sub_success_cb, $sub_fail_cb) = @_;
        is $sub->destination, $QUEUE;
        is $sub->id, $QUEUE;
        $subscribed->send(1);
        return 1;
    });
    $client = AnyEvent::STOMP->connect( 'localhost', $PORT, 0, $QUEUE, undef );
    $client->reg_cb( connect_error => sub { diag $_[1]; $connected->send(0) } );
    my $io_error = $client->reg_cb( io_error => sub { $connected->send(0); } );
    $client->reg_cb( CONNECTED => sub { $connected->send(1); });
    ok $connected->recv;
    ok $subscribed->recv;
    $client->unreg_cb( $io_error );

    my $got_message = AE::cv;
    $io_error = $client->reg_cb( io_error => sub { $got_message->send(0); } );
    $client->reg_cb( MESSAGE => sub {
        diag Dump(\@_);
        $got_message->send(1);
    });
    $backend->inject_message($QUEUE, \"hello world message", { });
    #$got_message->recv;
    undef $client; # disconnect
    
    
}

ok 1;

__END__
