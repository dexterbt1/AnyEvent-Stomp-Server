use strict;
use Test::More tests => 36;

BEGIN {
    use_ok 'AnyEvent::Stomp::Server';
    use_ok 'AnyEvent::Stomp::Server::Constants', '-all';
    use_ok 'YAML';
    require 't/MockBackend.pm';
    require 't/StompClient.pm';
}

my $PORT = 16163;

my $backend = MockBackend->new;
my $server = AnyEvent::Stomp::Server->new( listen_port => $PORT, backend => $backend ); 
#$AnyEvent::Stomp::Server::Session::DEBUG = 1;

my $client;

$backend->connect_obs(sub { 1 });

{
    pass "v1.0 subscribe";
    # connect
    my $connected = AE::cv;
    my $subscribed = AE::cv;
    $backend->subscribe_obs(sub {
        my ($be, $sess, $sub, $sub_success_cb, $sub_fail_cb) = @_;
        is $sub->destination, 'foo';
        is $sub->ack, STOMP_ACK_AUTO,
        $subscribed->send(1);
        return 1;
    });
    $client = StompClient->connect( 'localhost', $PORT, 0, 'foo', undef );
    $client->reg_cb( connect_error => sub { diag $_[1]; $connected->send(0) } );
    $client->reg_cb( io_error => sub { diag $_[1]; $connected->send(0); } );
    $client->reg_cb( CONNECTED => sub { $connected->send(1); });
    ok $connected->recv;
    ok $subscribed->recv;
    $client->{handle}->destroy; # force disconnect
}

{
    pass "v1.0 backend subscribe failed";
    # connect
    my $io_error = AE::cv;
    my $backend_subscribe_called = 0;
    $backend->subscribe_obs(sub {
        $backend_subscribe_called = 1;
        return 0; # failed
    });
    $client = StompClient->connect( 'localhost', $PORT, 0, 'devnull', undef );
    $client->reg_cb( connect_error => sub { diag $_[1]; $io_error->send(0); } ); 
    $client->reg_cb( io_error => sub { $io_error->send(1); } ); # expect disconnect
    ok $io_error->recv;
    ok $backend_subscribe_called;
    $client->{handle}->destroy; # force disconnect
}

{
    pass "v1.0 subscribe w/ receipt + headers";
    # connect
    my $connected = AE::cv;
    my $subscribed = AE::cv;
    $backend->subscribe_obs(sub {
        my ($be, $sess, $sub, $sub_success_cb, $sub_fail_cb) = @_;
        is $sub->destination, 'foo_bar';
        is $sub->id, 'foo_bar';
        is $sub->ack, STOMP_ACK_CLIENT, 'ack=client';
    });
    $client = StompClient->connect( 'localhost', $PORT, 0, 'foo_bar', undef, undef, { 'prefetch-size' => 1, 'receipt' => '123abc', 'ack' => 'client' } );
    $client->reg_cb( connect_error => sub { diag $_[1]; $connected->send(0) } );
    $client->reg_cb( io_error => sub { diag $_[1]; $connected->send(0); } );
    $client->reg_cb( CONNECTED => sub { $connected->send(1); });
    $client->reg_cb( RECEIPT => sub { 
        my $headers = $_[2];
        is $headers->{'receipt-id'}, '123abc';
        $subscribed->send(1); 
    });
    ok $connected->recv, 'connected';
    ok $subscribed->recv;
    $client->{handle}->destroy; # force disconnect
}

{
    pass "v1.0 subscribe w/out destination";
    # connect
    my $connected = AE::cv;
    my $subscribed = AE::cv;
    my $backend_subscribe_not_called = 1;
    $backend->subscribe_obs(sub {
        $backend_subscribe_not_called = 0;
        return 1;
    });
    $client = StompClient->connect( 'localhost', $PORT, 0, undef, undef, undef );
    $client->reg_cb( connect_error => sub { diag $_[1]; $connected->send(0); $subscribed->send(0); } );
    $client->reg_cb( io_error => sub { diag $_[1]; $connected->send(0); $subscribed->send(0); } );
    $client->reg_cb( CONNECTED => sub { 
        $connected->send(1); 
        $client->send_frame( SUBSCRIBE => '', { 'receipt' => '1234' } );
    });
    $client->reg_cb( ERROR => sub { 
        # expect an error
        my $headers = $_[2];
        is $headers->{'receipt-id'}, '1234';
        $subscribed->send(0); 
    });
    ok $connected->recv;
    ok not($subscribed->recv);
    ok $backend_subscribe_not_called;
    $client->{handle}->destroy; # force disconnect
}

{
    pass "v1.1 subscribe w/out id";
    # connect
    my $connected = AE::cv;
    my $subscribed = AE::cv;
    my $backend_subscribe_not_called = 1;
    $backend->subscribe_obs(sub {
        $backend_subscribe_not_called = 0;
        return 1;
    });
    $client = StompClient->connect( 'localhost', $PORT, 0, undef, undef, { 'accept-version' => '1.1' } );
    $client->reg_cb( connect_error => sub { diag $_[1]; $connected->send(0); $subscribed->send(0); } );
    $client->reg_cb( io_error => sub { diag $_[1]; $connected->send(0); $subscribed->send(0); } );
    $client->reg_cb( CONNECTED => sub { 
        $connected->send(1); 
        $client->send_frame( SUBSCRIBE => '', { 'receipt' => '1234' } );
    });
    $client->reg_cb( ERROR => sub { 
        # expect an error
        my $headers = $_[2];
        is $headers->{'receipt-id'}, '1234';
        $subscribed->send(0); 
    });
    ok $connected->recv;
    ok not($subscribed->recv);
    ok $backend_subscribe_not_called;
    $client->{handle}->destroy; # force disconnect
}


{
    pass "v1.1 subscribe ok w/ receipt";
    my $connected = AE::cv;
    my $subscribe_receipt = AE::cv;
    $backend->subscribe_obs(sub {
        my ($be, $sess, $sub, $sub_success_cb, $sub_fail_cb) = @_;
        is $sub->destination, 'foo';
        is $sub->id, '1';
        is $sub->ack, STOMP_ACK_INDIVIDUAL;
        return 1;
    });
    $client = StompClient->connect( 'localhost', $PORT, 0, undef, undef, { 'accept-version' => '1.1' } );
    $client->reg_cb( connect_error => sub { diag $_[1]; $connected->send(0); $subscribe_receipt->send(0); } );
    $client->reg_cb( io_error => sub { diag $_[1]; $connected->send(0); $subscribe_receipt->send(0); } );
    $client->reg_cb( ERROR => sub { diag Dump($_[1]); $connected->send(0); $subscribe_receipt->send(0); } );
    $client->reg_cb( CONNECTED => sub { 
        $connected->send(1); 
        $client->send_frame( 
            SUBSCRIBE => '', 
            { 'destination' => 'foo', 'receipt' => '1235', id => '1', ack => 'client-individual' },
        );
    });
    $client->reg_cb( RECEIPT => sub {
        my (undef, $body, $headers) = @_;
        is $headers->{'receipt-id'}, '1235';
        $subscribe_receipt->send(1);
    });
    ok $connected->recv;
    ok $subscribe_receipt->recv;
    $client->{handle}->destroy; # force disconnect
}


ok 1;

__END__

