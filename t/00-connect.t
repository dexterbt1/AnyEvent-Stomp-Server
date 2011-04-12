use strict;
use Test::More qw/no_plan/;

BEGIN {
    use_ok 'AnyEvent::Stomp::Broker';
    use_ok 'AnyEvent::STOMP';
    use_ok 'YAML';
}

my $PORT = 16163;

my $server = AnyEvent::Stomp::Broker->new( listen_port => $PORT );

my $done;
my $client;

# basic connect
{
    $done = AE::cv;
    $client = AnyEvent::STOMP->connect( 'localhost', $PORT, 0, undef, undef );
    $client->reg_cb( connect_error => sub { diag $_[1]; $done->(0) } );
    $client->reg_cb( io_error => sub { diag $_[1]; $done->(0); } );
    $client->reg_cb( CONNECTED => sub {
        my ($c, $body, $headers) = @_;
        ok exists $headers->{'session-id'};
        ok exists $headers->{'server'};
        is $headers->{'version'}, '1.0';
        $done->(1);
    });
    ok $done->recv;
    undef $client; # disconnect
}

# protocol negotiation unsupported
{
    $done = AE::cv;
    $client = AnyEvent::STOMP->connect( 'localhost', $PORT, 0, undef, undef, { 'accept-version' => '12.34' } );
    $client->reg_cb( connect_error => sub { diag $_[1]; $done->(0) } );
    $client->reg_cb( io_error => sub { diag $_[1]; $done->(0); } );
    $client->reg_cb( ERROR => sub { $done->(1); });
    ok $done->recv;
    undef $client; # disconnect
}

# protocol negotiation ok
{
    $done = AE::cv;
    $client = AnyEvent::STOMP->connect( 'localhost', $PORT, 0, undef, undef, { 'accept-version' => '1.1' } );
    $client->reg_cb( connect_error => sub { diag $_[1]; $done->(0) } );
    $client->reg_cb( io_error => sub { diag $_[1]; $done->(0); } );
    $client->reg_cb( CONNECTED => sub {
        my ($c, $body, $headers) = @_;
        ok exists $headers->{'session-id'};
        ok exists $headers->{'server'};
        is $headers->{'version'}, '1.1';
        $done->(1);
    });
    ok $done->recv;
    undef $client; # disconnect
}

ok 1;

__END__
