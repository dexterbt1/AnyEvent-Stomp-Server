package AnyEvent::Stomp::Broker::Session;
use strict;
use Class::Load ':all';
use Moose;
use YAML;
use Scalar::Util qw/refaddr/;

our $DEBUG = 0;
our $DEFAULT_PROTOCOL = '1.0';
our %SERVER_PROTOCOLS = (
    '1.0'   => 1,
    '1.1'   => 1,
);

has 'parent_broker'         => ( is => 'rw', isa => 'AnyEvent::Stomp::Broker', weak_ref => 1 );

has 'socket'                => ( is => 'rw', isa => 'GlobRef', required => 1, );
has 'host'                  => ( is => 'rw', isa => 'Any', required => 1 );
has 'port'                  => ( is => 'rw', isa => 'Any', required => 1 );
has 'handle_class'          => ( is => 'rw', isa => 'Str', lazy => 1, default => 'AnyEvent::Handle' );
has 'handle'                => ( is => 'rw', isa => 'Any' );

has 'is_connected'          => ( is => 'rw', isa => 'Bool', lazy => 1, default => 0 );
has 'protocol_version'      => ( is => 'rw', isa => 'Any' );
has 'session_id'            => ( is => 'rw', isa => 'Any' );


sub BUILD {
    my ($self) = @_;
    load_class $self->handle_class;
    my $ch;
    binmode $self->socket;
    $ch = $self->handle_class->new(
        fh          => $self->socket,
        on_error    => sub { 
            $self->disconnect($_[2]); 
        },
        on_eof      => sub { 
            $self->disconnect("Client socket disconnected"); 
        },
        on_read     => sub { 
            $self->read_frame(@_); 
        },
    );
    $self->handle($ch);
    $self->session_id( refaddr($self) );
}


sub read_frame {
    my ($self, $ch) = @_;
    $ch->push_read( 'AnyEvent::Stomp::Broker::Frame' => sub {
        my $frame = $_[1];
        ($DEBUG) && do { print STDERR "Broker received: ".Dump($frame); };

        if (not $self->is_connected) {
            # client did not issue a CONNECT yet
            if ($frame->{command} eq 'CONNECT') {
                $self->protocol_version( $DEFAULT_PROTOCOL );
                my $response_frame = Net::Stomp::Frame->new({
                    command => 'CONNECTED',
                    headers => {
                        "session"       => sprintf("%s",$self->session_id),
                        "version"       => $self->protocol_version,
                        "server"        => ref($self->parent_broker),
                    },
                    body => '',
                });
                # TODO: MAY disallow CONNECTs w/ 'receipt' header
                # TODO: SHOULD add authentication
                # TODO: MAY support virtual hosting

                # protocol negotiation: choose the highest version supported by both server and client
                # ----------------
                if (exists $frame->{headers}->{'accept-version'}) {
                    my $proto_version = '';
                    my @client_versions = split /\s*,\s*/, $frame->{headers}->{'accept-version'};
                    my %client_supported = map { $_ => 1 } @client_versions;
                    foreach my $sv (sort keys %SERVER_PROTOCOLS) {
                        if (exists $client_supported{$sv}) {
                            $proto_version = $sv;
                        }
                    }
                    if (not $proto_version) {
                        $self->send_client_error( "Supported protocol versions are: ".join(', ', sort keys %SERVER_PROTOCOLS), $frame );
                        $self->disconnect("Unsupported client protocol version: ".$self);
                        return;
                    }
                    $response_frame->{headers}->{'version'} = $proto_version;
                    $self->protocol_version( $proto_version );
                }

                $self->send_client_frame( $response_frame );
                $self->is_connected( 1 );
                return 1;
            }
            else {
                $self->send_client_error( 'Not yet connected', $frame );
                $self->disconnect("Client did not issue a proper CONNECT: ".$self);
            }
        }
        else {
            # already connected
            # -----------------
            no warnings 'uninitialized';
            if ($frame->{command} eq 'DISCONNECT') {
                $self->disconnect("Explicit DISCONNECT frame from client: ".$self);
            }
            elsif ($frame->{command} eq 'SEND') {
                $self->parent_broker->backend->send($self, $frame);
            }
            elsif ($frame->{command} eq 'SUBSCRIBE') {
                # validate subscribe frame
                (exists $frame->{headers}->{'destination'})
                    or do {
                        $self->send_client_error( 'SUBSCRIBE header "destination" required', $frame);
                        return;
                    };
                my $subscription_id = $frame->{headers}->{'destination'};
                if ($self->protocol_version eq '1.1') {
                    # Stomp 1.1 checks
                    (exists $frame->{headers}->{'id'})
                        or do {
                            $self->send_client_error( 'SUBSCRIBE header "id" required', $frame);
                            return;
                        };
                    $subscription_id = $frame->{headers}->{'id'};
                }
                # TODO: policy for repeat subscription_id
                $self->parent_broker->backend->subscribe($self, $frame, $subscription_id);
            }
            else {
                # unexpected frame
                $self->send_client_error( 'Unexpected frame', $frame );
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
    #print STDERR "disconnect: $reason\n" if ($reason);
    undef $self;
}


sub send_client_frame {
    my ($self, $frame) = @_;
    $self->handle->push_write( $frame->as_string );
    ($DEBUG) && do { print STDERR "Broker sent: ".Dump($frame); };
}


sub send_client_receipt {
    my ($self, $receipt_id) = @_;
    $self->send_client_frame( Net::Stomp::Frame->new({ command => 'RECEIPT', headers => { 'receipt-id' => $receipt_id }, body => '' }) );
}


sub send_client_error {
    my ($self, $message, $original_frame) = @_;
    my $f = Net::Stomp::Frame->new({ command => 'ERROR', headers => { 'content-type' => 'text/plain' }, body => $message."\n" });
    if ($original_frame && exists($original_frame->{headers}->{'receipt'})) { 
        $f->{headers}->{'receipt-id'} = $original_frame->{headers}->{'receipt'};
    }
    $f->{headers}->{bytes_message} = 1; # FIXME: hardcode feature from Net::Stomp
    $self->send_client_frame( $f );
}

1;

__END__
