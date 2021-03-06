use strict;
use Test::More tests => 14;

BEGIN {
    use_ok 'AnyEvent::Stomp::Server';
    use_ok 'YAML';
    require 't/MockBackend.pm';
    require 't/StompClient.pm';
}

my $PORT = 16163;

my $backend = MockBackend->new;
my $server = AnyEvent::Stomp::Server->new( listen_port => $PORT, backend => $backend );

# basic connect
{
    my $done = AE::cv;
    my $connected = 0;
    $backend->connect_obs(sub {
        $connected = 1;
        return 1;
    });
    my $client = StompClient->connect( 'localhost', $PORT, 0, undef, undef );
    $client->reg_cb( connect_error => sub { diag $_[1]; $done->send(0) } );
    $client->reg_cb( io_error => sub { diag $_[1]; $done->send(0); } );
    $client->reg_cb( CONNECTED => sub {
        my ($c, $body, $headers) = @_;
        ok exists $headers->{'session'};
        ok exists $headers->{'server'};
        is $headers->{'version'}, '1.0';
        $done->send(1);
    });
    ok $done->recv;
    ok $connected;
    $client->{handle}->destroy; # force disconnect
}

# protocol negotiation unsupported
{
    my $done = AE::cv;
    $backend->connect_obs(sub { 1 });
    my $client = StompClient->connect( 'localhost', $PORT, 0, undef, undef, { 'accept-version' => '12.34' } );
    $client->reg_cb( connect_error => sub { diag $_[1]; $done->send(0) } );
    $client->reg_cb( io_error => sub { $done->send(1); } ); # expects disconnect
    $client->reg_cb( ERROR => sub { $done->send(1); }); # expect error frame, if we ever get this
    ok $done->recv;
    $client->{handle}->destroy; # force disconnect
}

# protocol negotiation ok
{
    my $done = AE::cv;
    $backend->connect_obs(sub { 1 });
    my $client = StompClient->connect( 'localhost', $PORT, 0, undef, undef, { 'accept-version' => '1.1' } );
    $client->reg_cb( connect_error => sub { diag $_[1]; $done->send(0) } );
    $client->reg_cb( io_error => sub { diag $_[1]; $done->send(0); } );
    $client->reg_cb( CONNECTED => sub {
        my ($c, $body, $headers) = @_;
        ok exists $headers->{'session'};
        ok exists $headers->{'server'};
        is $headers->{'version'}, '1.1';
        $done->send(2);
    });
    my $x = $done->recv;
    ok $x;
    undef $client; # disconnect
}

# failed backend
{
    my $done = AE::cv;
    $backend->connect_obs(sub { 0 });
    my $client = StompClient->connect( 'localhost', $PORT, 0, undef, undef );
    $client->reg_cb( connect_error => sub { diag $_[1]; $done->send(0) } );
    $client->reg_cb( io_error => sub { $done->send(1); } ); # expects disconnect
    $client->reg_cb( ERROR => sub { $done->send(1); }); # expect error frame, if we ever get this
    ok $done->recv;
    $client->{handle}->destroy; # force disconnect
}


pass "nop";

__END__
