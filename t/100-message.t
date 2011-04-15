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

{
    pass "subscribe dest=foo then disconnect";
    # connect
    my $connected = AE::cv;
    my $subscribed = AE::cv;
    $backend->subscribe_obs(sub {
        my ($be, $sub, $sub_success_cb, $sub_fail_cb) = @_;
        $subscribed->send(1);
        return 1;
    });
    my $client = AnyEvent::STOMP->connect( 'localhost', $PORT, 0, 'foo', undef );
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
    $client->{handle}->destroy; # force disconnect
    ok $disconnected->recv;
    
}

{
    # note, this is the 2nd test, the backend previously got a subscription to foo, but the client disconnected
    pass "subscribe dest=foo, then simulate a MESSAGE";
    # connect
    my $QUEUE = 'foo';
    my $connected = AE::cv;
    my $subscribed = AE::cv;
    $backend->subscribe_obs(sub {
        my ($be, $sub, $sub_success_cb, $sub_fail_cb) = @_;
        is $sub->destination, $QUEUE;
        is $sub->id, $QUEUE;
        is $sub->ack, STOMP_ACK_AUTO;
        $subscribed->send(1);
        return 1;
    });
    my $client = AnyEvent::STOMP->connect( 'localhost', $PORT, 0, $QUEUE, undef );
    $client->reg_cb( connect_error => sub { diag $_[1]; $connected->send(0) } );
    my $io_error = $client->reg_cb( io_error => sub { $connected->send(0); } );
    $client->reg_cb( CONNECTED => sub { $connected->send(1); });
    ok $connected->recv;
    ok $subscribed->recv;
    $client->unreg_cb( $io_error );

    my $got_message = AE::cv;
    $io_error = $client->reg_cb( io_error => sub { $got_message->send(0); } );
    $client->reg_cb( MESSAGE => sub {
        my (undef, $body, $headers) = @_;
        ok $headers->{'message-id'}, 'message-id';
        is $headers->{'destination'}, $QUEUE;
        is $headers->{'subscription'}, $QUEUE;
        is $body, "hello world message";
        $got_message->send(1);
    });
    $backend->inject_message($QUEUE, \"hello world message", { });
    $got_message->recv;

    $client->{handle}->destroy; # force disconnect
}



{
    # note, this is the 2nd test, the backend previously got a subscription to foo, but the client disconnected
    pass "subscribe dest=foo, ack=client, then simulate a MESSAGE";
    # connect
    my $QUEUE = 'foo';
    my $connected = AE::cv;
    my $subscribed = AE::cv;
    $backend->subscribe_obs(sub {
        my ($be, $sub, $sub_success_cb, $sub_fail_cb) = @_;
        is $sub->destination, $QUEUE;
        is $sub->id, $QUEUE;
        is $sub->ack, STOMP_ACK_CLIENT;
        $subscribed->send(1);
        return 1;
    });
    my $client = AnyEvent::STOMP->connect( 'localhost', $PORT, 0, $QUEUE, undef, { }, { 'ack' => 'client' } );
    $client->reg_cb( connect_error => sub { diag $_[1]; $connected->send(0) } );
    my $io_error = $client->reg_cb( io_error => sub { $connected->send(0); } );
    $client->reg_cb( CONNECTED => sub { $connected->send(1); });
    ok $connected->recv;
    ok $subscribed->recv;
    $client->unreg_cb( $io_error );

    my $got_message = AE::cv;
    $io_error = $client->reg_cb( io_error => sub { $got_message->send(0); } );
    $client->reg_cb( MESSAGE => sub {
        my (undef, $body, $headers) = @_;
        ok $headers->{'message-id'}, 'message-id';
        is $headers->{'destination'}, $QUEUE;
        is $headers->{'subscription'}, $QUEUE;
        is $body, "hello world message";
        $got_message->send(1);
    });
    $backend->inject_message($QUEUE, \"hello world message", { });
    $got_message->recv;
    undef $client; # disconnect
    
}


pass "end";

__END__
