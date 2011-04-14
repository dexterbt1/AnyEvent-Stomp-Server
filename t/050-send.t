use strict;
use Test::More tests => 27;

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

{
    pass "empty send";
    my $connected = AE::cv;
    $client = AnyEvent::STOMP->connect( 'localhost', $PORT, 0, undef, undef );
    $client->reg_cb( connect_error => sub { diag $_[1]; $connected->send(0) } );
    $client->reg_cb( io_error => sub { diag $_[1]; $connected->send(0); } );
    $client->reg_cb( CONNECTED => sub { $connected->send(1); });
    ok $connected->recv;
    
    my $error = AE::cv;
    $client->reg_cb( io_error => sub { diag $_[1]; $error->send(0); } );
    $client->reg_cb( ERROR => sub { $error->send(1); });
    $client->send_frame('SEND', '', { });
    ok $error;
    
}

{
    pass "minimal send";
    # connect
    my $connected = AE::cv;
    my $sent = AE::cv;
    $backend->send_obs( sub {
        my ($be,$dest,$headers,$bodyref,$success_cb,$fail_cb) = @_;
        is $dest, 'foo';
        ok not(exists $headers->{'receipt'});
        ok not(exists $headers->{'destination'});
        is $$bodyref, 'hello world';
        $sent->send(1);
        return 1;
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

{
    pass "send w/ receipt + extra headers";
    # connect
    my $connected = AE::cv;
    my $sent = AE::cv;
    $backend->send_obs( sub {
        my ($be,$dest,$headers,$bodyref,$success_cb,$fail_cb) = @_;
        is $dest, 'foo2';
        ok not(exists $headers->{'receipt'});
        ok not(exists $headers->{'destination'});
        is $headers->{'content-type'}, 'text/plain';
        is $$bodyref, 'hello world2';
        $sent->send(1);
        return 1;
    });
    $client = AnyEvent::STOMP->connect( 'localhost', $PORT, 0, undef, undef );
    $client->reg_cb( connect_error => sub { diag $_[1]; $connected->send(0) } );
    $client->reg_cb( io_error => sub { diag $_[1]; $connected->send(0); } );
    $client->reg_cb( CONNECTED => sub { $connected->send(1); });
    ok $connected->recv;
    my $receipt = AE::cv;
    $client->reg_cb( RECEIPT => sub { 
        my (undef, $body, $headers) = @_;
        is $headers->{'receipt-id'}, '1234';
        $receipt->send(1); 
    });
    $client->send('hello world2', 'foo2', { 'receipt' => '1234', 'content-type' => 'text/plain' });
    ok $sent->recv;
    ok $receipt->recv;
    undef $client; # disconnect
}

{
    pass "send backend fail";
    # connect
    my $connected = AE::cv;
    $backend->send_obs( sub { 0 } ); # simulate backend failure
    $client = AnyEvent::STOMP->connect( 'localhost', $PORT, 0, undef, undef );
    $client->reg_cb( connect_error => sub { diag $_[1]; $connected->send(0) } );
    my $ioerr = $client->reg_cb( io_error => sub { diag $_[1]; $connected->send(0); } );
    $client->reg_cb( CONNECTED => sub { $connected->send(1); });
    ok $connected->recv;
    my $error = AE::cv;
    $client->unreg_cb( $ioerr );
    $client->reg_cb( io_error => sub { $error->send(1); } ); # expected io_error
    $client->send('hello error', 'err');
    ok $error->recv;
    undef $client;
}


ok 1;

__END__
