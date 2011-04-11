package AnyEvent::Stomp::Broker::Session;
use strict;
use Class::Load ':all';
use Moose;
use YAML;

our $DEFAULT_PROTOCOL = '1.0';
our $CRLF = "\n";
our $NULL = "\000";

has 'parent_broker'         => ( is => 'rw', isa => 'AnyEvent::Stomp::Broker', weak_ref => 1 );
has 'socket'                => ( is => 'rw', isa => 'GlobRef', required => 1, );
has 'host'                  => ( is => 'rw', isa => 'Any', required => 1 );
has 'port'                  => ( is => 'rw', isa => 'Any', required => 1 );
has 'handle_class'          => ( is => 'rw', isa => 'Str', lazy => 1, default => 'AnyEvent::Handle' );
has 'handle'                => ( is => 'rw', isa => 'Any' );
has 'is_connected'          => ( is => 'rw', isa => 'Bool', lazy => 1, default => 0 );
has 'protocol'              => ( is => 'rw', isa => 'Any' );
has 'protocol_classes'      => ( is => 'rw', isa => 'HashRef[Str]', lazy => 1, default => sub {
    {
        '1.0'       => 'AnyEvent::Stomp::Broker::Protocol::Stomp1_0',
        '1.1'       => 'AnyEvent::Stomp::Broker::Protocol::Stomp1_1',
    }
});

sub BUILD {
    my ($self) = @_;
    load_class $self->handle_class;
    my $ch;
    binmode $self->socket;
    $ch = $self->handle_class->new(
        fh          => $self->socket,
        on_error    => sub { $self->disconnect($_[2]); },
        on_eof      => sub { $self->disconnect("Client socket disconnected: ".$self); },
        on_read     => sub { $self->read_frame( @_ ) },
    );
    $self->handle($ch);
}


sub read_frame {
    my ($self, $ch) = @_;
    $ch->push_read( 'AnyEvent::Stomp::Broker::Frame' => sub {
        my $frame = $_[1];
        print STDERR Dump($frame);
        if (not $self->is_connected) {
            if ($frame->{command} eq 'CONNECT') {
                # TODO: add authentication
                # ----------------
                # TODO: virtual hosting
                # ----------------

                # protocol negotiation: choose the highest version supported by both server and client
                # ----------------
                my $proto_version = '';

                my @server_versions = sort { $b <=> $a } keys %{$self->protocol_classes};
                if (exists $frame->{headers}->{'accept-version'}) {
                    my @client_versions = split /\s*,\s*/, $frame->{headers}->{'accept-version'};
                    my %client_supported = map { $_ => 1 } @client_versions;
                    foreach my $sv (@server_versions) {
                        if (exists $client_supported{$sv}) {
                            $proto_version = $sv;
                        }
                    }
                }
                else {
                    $proto_version = $DEFAULT_PROTOCOL;
                }
                while (1) {
                    my $protocol_class = $self->protocol_classes->{$proto_version};
                    if (not $protocol_class) {
                        $self->handle->push_write( join($CRLF, "ERROR", sprintf("content-type:%s", 'text/plain'), '', 'Supported protocol version are '.join(",", @server_versions).$NULL ) );
                        $self->disconnect("Unsupported client protocol version");
                        last;
                    }
                    load_class $protocol_class;
                    my $proto = $protocol_class->new( parent_session => $self );
                    $self->protocol( $proto );
                    $self->protocol->connect( $frame );
                    last;
                }
            }
            else {
                $self->handle->push_write( join($CRLF, "ERROR", sprintf("content-type:%d", 'text/plain'), '', 'Not yet connected'.$NULL ) );
                $self->disconnect("Client did not issue a proper CONNECT: ".$self);
            }
        }
        else {
            if ($frame->{command} eq 'DISCONNECT') {
                $self->disconnect("Explicit DISCONNECT frame from client: ".$self);
            }
        }
    });
}


sub disconnect {
    my ($self, $reason) = @_;
    my $h = $self->handle;
    $self->handle( undef );
    $h->destroy;
    undef $h;
    print STDERR "$reason\n" if ($reason);
    undef $self;
}


sub send_client_frame {
    my ($self, $frame) = @_;
    $self->handle->push_write( $frame->as_string );
}



1;

__END__
