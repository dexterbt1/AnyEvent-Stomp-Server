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
    # stateful backend test 
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
    my $acked = AE::cv;
    $backend->ack_obs(sub {
        my ($be, $sess, $msg_id, $success_cb, $failure_cb) = @_;
        ok defined($msg_id);
        isa_ok $success_cb, 'CODE';
        isa_ok $failure_cb, 'CODE';
        $acked->send(1);
    });
    $backend->inject_message($QUEUE, \"hello world message", { });
    ok $got_message->recv, 'client-got-message';
    ok $acked->recv, 'backend-got-ack-from-session';
    $client->{handle}->destroy; # force disconnect
}



{
    # note, this is the 2nd test, the backend previously got a subscription to foo, but the client disconnected
    pass "v1.0 subscribe dest=foo, ack=client, then simulate a MESSAGE";
    my $hello2_id;
    my $hello2_sub;
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
        $hello2_sub = $sub;
        return 1;
    });
    my $client = AnyEvent::STOMP->connect( 'localhost', $PORT, 0, $QUEUE, undef, { }, { 'ack' => 'client' } );
    $client->reg_cb( connect_error => sub { diag $_[1]; $connected->send(0) } );
    my $io_error = $client->reg_cb( io_error => sub { $connected->send(0); } );
    $client->reg_cb( CONNECTED => sub { $connected->send(1); });
    ok $connected->recv;
    ok $subscribed->recv;

    # simulate 2 prefetch
    my $got_messages = AE::cv;
    $client->unreg_cb( $io_error );
    $io_error = $client->reg_cb( io_error => sub { $got_messages->send(0); } );
    my $message_handler; 
    $message_handler = $client->reg_cb( MESSAGE => sub {
        my (undef, $body, $headers) = @_;
        ok $headers->{'message-id'}, 'message-id';
        is $headers->{'destination'}, $QUEUE;
        is $headers->{'subscription'}, $QUEUE;
        is $body, "hello1";
        $client->unreg_cb( $message_handler );
        $message_handler = $client->reg_cb( MESSAGE => sub {
            my (undef, $body, $headers) = @_;
            ok $headers->{'message-id'}, 'message-id';
            is $headers->{'destination'}, $QUEUE;
            is $headers->{'subscription'}, $QUEUE;
            is $headers->{'user'}, 'john';
            is $body, "hello2";
            $got_messages->send(1);
            pass "got hello2";
            $hello2_id = $headers->{'message-id'};
            $client->unreg_cb( $message_handler );
        });
        pass "got hello1";
    });
    $backend->inject_message($QUEUE, \"hello1", { });
    $backend->inject_message($QUEUE, \"hello2", { "user" => "john" });
    ok $got_messages->recv;

    is scalar(keys %{$hello2_sub->session->pending_messages}), 2, '2-unacked';

    # ack
    my $error = AE::cv;
    $client->unreg_cb( $io_error );
    $io_error = $client->reg_cb( io_error => sub { diag $_[1]; $error->send(0); } );
    my $error_guard = $client->reg_cb( ERROR => sub {
        my ($undef, $body, $headers) = @_;
        $error->send(1);
    });
    $client->send_frame('ACK', '', { }); 
    ok $error->recv; # expected error frame due to missing message_id for v1.0 protocol
    
    #is scalar(keys %{$hello2_sub->session->pending_messages}), 0, '0-unacked';

    $client->{handle}->destroy; # force disconnect
}


pass "end";

__END__
