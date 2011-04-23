use Test::More tests => 14;
use strict;
use warnings;

BEGIN {
    use_ok 'AnyEvent::Stomp::Server::Frame';
    use_ok 'AnyEvent::Handle';
    use_ok 'AnyEvent::Socket';
    use_ok 'YAML';
}

my $CLASS = 'AnyEvent::Stomp::Server::Frame';
my $CRLF = $AnyEvent::Stomp::Server::Frame::CRLF;
my $HOST = 'localhost';
my $PORT = 16164;

my $o;
my $i;

$o = $CLASS->new;
isa_ok $o, $CLASS;

$o = $CLASS->new( command => 'CONNECT', headers => { 'accept-version' => '1.1' } );
is $o->command, 'CONNECT';
is $o->headers->{'accept-version'}, '1.1';
is $o->as_string, join($CRLF,"CONNECT","accept-version:1.1","content-length:0","","\000");

{
    # serialize
    my $tkey = "somekey:\n";
    my $tvalue = "hello\nworld:\\r";
    $o->headers->{$tkey} = $tvalue;
    $o->body_ref(\"the quick brown fox jumps over the lazy dog.");

    my $buf = join($CRLF,
        "CONNECT",
        "accept-version:1.1",
        "content-length:44",
        "somekey\\c\\n:hello\\nworld\\c\\\\r",
        "",
        "the quick brown fox jumps over the lazy dog."."\000",
    );
    is $o->as_string, $buf, 'as_string';

    # deserialize
    # start dummy server

    my $server = tcp_server undef, $PORT, sub {
        syswrite $_[0], $buf;                
    };

    my $read_done = AE::cv;

    my $ch = AnyEvent::Handle->new(
        connect => [ $HOST, $PORT ],
        on_error => sub {
            $read_done->send(0);
        },
    );
    $ch->push_read( 
        $CLASS => sub { 
            $read_done->send($_[1]);
        }
    );
    $i = $read_done->recv;
    #diag Dump($i);
    is $i->command, $o->command;
    is $i->headers->{'accept-version'}, $o->headers->{'accept-version'};
    is $i->headers->{$tkey}, $o->headers->{$tkey};
    is $i->body_as_string, $o->body_as_string;
}



ok 1;


__END__
