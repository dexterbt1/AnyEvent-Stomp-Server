use strict;
use Test::More qw/no_plan/;

BEGIN {
    use_ok 'AnyEvent::Stomp::Broker';
    use_ok 'AnyEvent::STOMP';
    use_ok 'YAML';
    require 't/MockBackend.pm';
}

my $PORT = 16163;

my $backend = MockBackend->new;
my $server = AnyEvent::Stomp::Broker->new( listen_port => $PORT, backend => $backend ); 

my $client;

# subscribe
{
    # connect
    my $connected = AE::cv;
    my $subscribed = AE::cv;
    $backend->subscribe_cb(sub {
        my (undef, undef, $frame) = @_;
        is $frame->{headers}->{'destination'}, 'foo';
        $subscribed->send(1);
    });
    $client = AnyEvent::STOMP->connect( 'localhost', $PORT, 0, 'foo', undef );
    $client->reg_cb( connect_error => sub { diag $_[1]; $connected->send(0) } );
    $client->reg_cb( io_error => sub { diag $_[1]; $connected->send(0); } );
    $client->reg_cb( CONNECTED => sub { $connected->send(1); });
    ok $connected->recv;
    ok $subscribed->recv;
    undef $client; # disconnect
}

# subscribe w/ receipt + headers
{
    # connect
    my $connected = AE::cv;
    my $subscribed = AE::cv;
    $backend->subscribe_cb(sub {
        my (undef, $sess, $frame) = @_;
        is $frame->{headers}->{'destination'}, 'foo';
        is $frame->{headers}->{'receipt'}, '123abc';
        is $frame->{headers}->{'ack'}, 'client';
        is $frame->{headers}->{'prefetch-size'}, 1;
        $sess->send_client_receipt( $frame->{headers}->{'receipt'} ); # mocked receipt
    });
    $client = AnyEvent::STOMP->connect( 'localhost', $PORT, 0, 'foo', undef, undef, { 'prefetch-size' => 1, 'receipt' => '123abc', 'ack' => 'client' } );
    $client->reg_cb( connect_error => sub { diag $_[1]; $connected->send(0) } );
    $client->reg_cb( io_error => sub { diag $_[1]; $connected->send(0); } );
    $client->reg_cb( CONNECTED => sub { $connected->send(1); });
    $client->reg_cb( RECEIPT => sub { 
        my $headers = $_[2];
        is $headers->{'receipt-id'}, '123abc';
        $subscribed->send(1); 
    });
    ok $connected->recv;
    ok $subscribed->recv;
    undef $client; # disconnect
}

# v1.0 subscribe w/out destination
{
    # connect
    my $connected = AE::cv;
    my $subscribed = AE::cv;
    my $backend_subscribe_not_called = 1;
    $backend->subscribe_cb(sub {
        $backend_subscribe_not_called = 0;
    });
    $client = AnyEvent::STOMP->connect( 'localhost', $PORT, 0, undef, undef, undef );
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
    undef $client; # disconnect
}

# v1.1 subscribe w/out id
{
    # connect
    my $connected = AE::cv;
    my $subscribed = AE::cv;
    my $backend_subscribe_not_called = 1;
    $backend->subscribe_cb(sub {
        $backend_subscribe_not_called = 0;
    });
    $client = AnyEvent::STOMP->connect( 'localhost', $PORT, 0, undef, undef, { 'accept-version' => '1.1' } );
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
    undef $client; # disconnect
}


ok 1;

__END__

