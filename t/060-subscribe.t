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


ok 1;

__END__

