use strict;
use Test::More tests => 9;

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

# basic send
{
    # connect
    my $connected = AE::cv;
    my $sent = AE::cv;
    $backend->send_cb( sub {
        my (undef,undef,$frame) = @_;
        is $frame->{command}, 'SEND';
        is $frame->{headers}->{'destination'}, 'foo';
        is $frame->{body}, 'hello world';
        $sent->send(1)
    });
    $client = AnyEvent::STOMP->connect( 'localhost', $PORT, 0, undef, undef );
    $client->reg_cb( connect_error => sub { diag $_[1]; $connected->send(0) } );
    $client->reg_cb( io_error => sub { diag $_[1]; $connected->send(0); } );
    $client->reg_cb( CONNECTED => sub { $connected->send(1); });
    ok $connected->recv;
    # send and ensure backend gets the frame
    $client->send('hello world', 'foo');
    ok $sent->recv;
    undef $client; # disconnect
}


ok 1;

__END__
