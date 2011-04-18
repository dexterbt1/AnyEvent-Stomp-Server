package AnyEvent::Stomp::Broker::Session;
use strict;
use Moose;
use YAML;
use Class::Load ':all';
use Scalar::Util qw/refaddr weaken/;
use AnyEvent::Stomp::Broker::Session::Subscription;
use AnyEvent::Stomp::Broker::Constants '-all';

with 'AnyEvent::Stomp::Broker::Role::Session';

our $DEBUG = 0;
our $DEFAULT_PROTOCOL = '1.0';
our %SERVER_PROTOCOLS = (
    '1.0'   => 1,
    '1.1'   => 1,
);

has 'parent_broker'         => ( is => 'rw', isa => 'AnyEvent::Stomp::Broker', weak_ref => 1 );

has 'socket'                => ( is => 'rw', isa => 'GlobRef', required => 1, weak_ref => 1 );
has 'host'                  => ( is => 'rw', isa => 'Any', required => 1 );
has 'port'                  => ( is => 'rw', isa => 'Any', required => 1 );
has 'handle_class'          => ( is => 'rw', isa => 'Str', lazy => 1, default => 'AnyEvent::Handle' );
has 'handle'                => ( is => 'rw', isa => 'Any' );

has 'pending_connect'       => ( is => 'rw', isa => 'Bool', lazy => 1, default => 0 );
has 'is_connected'          => ( is => 'rw', isa => 'Bool', lazy => 1, default => 0 );
has 'protocol_version'      => ( is => 'rw', isa => 'Any' );

has 'pending_messages'          => ( is => 'rw', isa => 'HashRef[Str]', lazy => 1, default => sub { { } } );
# {
#   $msg_id => [ $sub, $body_ref, $headers ],
#   ...  # not used when ack != auto
# }

has 'pending_messages_order'    => ( is => 'rw', isa => 'ArrayRef', lazy => 1, default => sub { [ ] } );
# [
#   $msg_id_1, 
#   $msg_id_2, 
#   ... # in the order as they were received from the backend
#       # not used when ack=client-individual
# ]


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
    $self->session_id( 'sessid-'.refaddr($self) );
}


sub DEMOLISH {
    my ($self) = @_;
    ($DEBUG) && print STDERR __PACKAGE__."->DEMOLISH() called ...\n";
    if ($self->is_connected) {
        weaken $self;
        $self->parent_broker->backend->disconnect($self);
    }
}


sub read_frame {
    my ($self, $ch) = @_;
    weaken $ch;
    $ch->push_read( 'AnyEvent::Stomp::Broker::Frame' => sub {
        my $frame = $_[1];
        ($DEBUG) && do { print STDERR "Session received: ".Dump($frame); };

        if (not $self->is_connected) {
            # client did not issue a CONNECT yet
            if (($frame->command eq 'CONNECT') and not($self->pending_connect)) {
                $self->protocol_version( $DEFAULT_PROTOCOL );
                my $response_frame = AnyEvent::Stomp::Broker::Frame->new(
                    command => 'CONNECTED',
                    headers => {
                        "session"       => sprintf("%s",$self->session_id),
                        "version"       => $self->protocol_version,
                        "server"        => ref($self->parent_broker),
                    },
                );
                # TODO: MAY disallow CONNECTs w/ 'receipt' header
                # TODO: SHOULD add authentication
                # TODO: MAY support virtual hosting

                # protocol negotiation: choose the highest version supported by both server and client
                # ----------------
                if (exists $frame->headers->{'accept-version'}) {
                    my $proto_version = '';
                    my @client_versions = split /\s*,\s*/, $frame->headers->{'accept-version'};
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
                    $response_frame->headers->{'version'} = $proto_version;
                    $self->protocol_version( $proto_version );
                }

                $self->pending_connect(1);
                weaken $self;
                $self->parent_broker->backend->connect(
                    $self,
                    sub {
                        $self->send_client_frame( $response_frame );
                        $self->is_connected( 1 );
                        $self->pending_connect(0);
                    },
                    sub {
                        my ($reason, $sess) = @_;
                        $self->send_client_error( 'Unable to CONNECT, backend error: '.$reason, $frame );
                        $self->disconnect($reason);
                    },
                );
                return;
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
            if ($frame->command eq 'DISCONNECT') {
                $self->disconnect("Explicit DISCONNECT frame from client: ".$self);
            }
            elsif ($frame->command eq 'SEND') {
                $self->handle_frame_send( $frame );
            }
            elsif ($frame->command eq 'SUBSCRIBE') {
                $self->handle_frame_subscribe( $frame );
            }
            elsif ($frame->command eq 'ACK') {
                $self->handle_frame_ack( $frame );
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
    $h->destroy;
    undef $h;
    #print STDERR "disconnect: $reason\n" if ($reason);
    undef $self;
}


sub send_client_frame {
    my ($self, $frame) = @_;
    return if ($self->handle->destroyed);
    $self->handle->push_write( $frame->as_string );
    ($DEBUG) && do { print STDERR "Session sent: ".Dump($frame); };
}


sub send_client_receipt {
    my ($self, $receipt_id, $opt_headers) = @_;
    my $headers = (defined $opt_headers) ? $opt_headers : { };
    $headers->{'receipt-id'} = $receipt_id;
    $self->send_client_frame( AnyEvent::Stomp::Broker::Frame->new( command => 'RECEIPT', headers => $headers, ) );
}


sub send_client_error {
    my ($self, $message, $original_frame) = @_;
    no warnings 'uninitialized';
    ($DEBUG) && do { print STDERR "client_error: ".$message."\n"; };
    my $f = AnyEvent::Stomp::Broker::Frame->new( command => 'ERROR', headers => { 'message' => $message || '' } );
    if ($original_frame && exists($original_frame->{headers}->{'receipt'})) { 
        $f->{headers}->{'receipt-id'} = $original_frame->{headers}->{'receipt'};
    }
    $self->send_client_frame( $f );
}


sub send_client_message {
    my ($self, $sub, $msg_id, $dest, $body_ref, $headers) = @_;
    my $message_frame = AnyEvent::Stomp::Broker::Frame->new(
        command => 'MESSAGE',
        headers => $headers,
        body_ref => $body_ref,
    );
    $message_frame->headers->{'message-id'} = $msg_id;
    $message_frame->headers->{'destination'} = $dest;
    $message_frame->headers->{'subscription'} = $sub->id;
    $self->send_client_frame($message_frame);

    if ($sub->ack == STOMP_ACK_CLIENT) {
        # ack=client
        # ----------
        # mark message as pending
        push @{$self->pending_messages_order}, $msg_id;
        $self->pending_messages->{$msg_id} = [ $sub, $body_ref, $headers ];
        # ...
        # then wait for the client to send an ACK frame
        # ...
    }
    elsif ($sub->ack == STOMP_ACK_INDIVIDUAL) {
        # ack=client-individual
        # ---------------------
        # mark message as pending
        $self->pending_messages->{$msg_id} = [ $sub, $body_ref, $headers ];
        # ...
        # then wait for the client to send an ACK frame
        # ...
    }
    elsif ($sub->ack == STOMP_ACK_AUTO) {
        # ack=auto
        # --------
        weaken $self;
        $self->parent_broker->backend->ack( 
            $self, 
            $msg_id,
            sub { 
                # successful ack
                # nop
            },
            sub { 
                # backend error during ack
                my ($reason, $sess, $msg_id) = @_;
                $self->send_client_error($reason);
            },
        );
    } 
}


sub ack_pending_message_cumulative {
    my ($self, $msg_id) = @_;
    my $idx;
    my $i = 0;
    foreach my $pm (@{$self->pending_messages_order}) {
        if ($pm eq $msg_id) {
            $idx = $i;
            last;
        }
        $i++;
    }
    if (defined $idx) {
        my @removed = splice @{$self->pending_messages_order}, 0, $idx+1;
        map { delete $self->pending_messages->{$_} } @removed;
    }
}


sub ack_pending_message_individual {
    my ($self, $msg_id) = @_;
    delete $self->pending_messages->{$msg_id};
}

# -----------------


sub handle_frame_ack {
    my ($self, $frame) = @_;
    # required message-id in 1.0,1.1
    if (not exists $frame->headers->{'message-id'}) {
        $self->send_client_error("ACK requires 'message-id' header", $frame);
        return;
    }

    my $msg_id;
    my $cl_sub_id;
    if ($self->protocol_version eq '1.1') {
        if (not exists $frame->headers->{'subscription'}) {
            $self->send_client_error("ACK requires 'subscription' header", $frame);
            return;
        }
        $cl_sub_id = $frame->headers->{'subscription'};
    }

    $msg_id = $frame->headers->{'message-id'};

    # validate existence
    if (not($msg_id) or not(exists $self->pending_messages->{$msg_id})) {
        $self->send_client_error(sprintf("ACK error for non-existent message-id '%s'", $msg_id), $frame);
        return;
    }

    my $sub = $self->pending_messages->{$msg_id}->[0];
    # validate subscription
    if (defined $cl_sub_id) {
        if ($sub->id ne $cl_sub_id) {
            $self->send_client_error(sprintf("ACK error for non-existent subscription '%s'", $cl_sub_id), $frame);
            return;
        }
    }

    weaken $self;
    $self->parent_broker->backend->ack(
        $self, 
        $msg_id,
        sub { 
            # successful ack
            if ($sub->ack == STOMP_ACK_CLIENT) {
                $self->ack_pending_message_cumulative( $msg_id );
            }
            elsif ($sub->ack == STOMP_ACK_INDIVIDUAL) {
                $self->ack_pending_message_individual( $msg_id );
            }
            if (exists $frame->headers->{'receipt'}) {
                $self->send_client_receipt( $frame->headers->{'receipt'} );
            }
        },
        sub { 
            # backend error during ack
            my ($reason, $sess, $msg_id) = @_;
            $self->send_client_error($reason);
        },
    );

}



sub handle_frame_send {
    my ($self, $frame) = @_;
    # 1.0 requires destination
    if (not exists $frame->headers->{'destination'}) {
        $self->send_client_error( 'SEND header "destination" required', $frame );
        return;
    }
    my $destination = delete $frame->headers->{'destination'};
    my $has_receipt = exists $frame->headers->{'receipt'};
    my $receipt_id  = delete $frame->headers->{'receipt'};
    weaken $self;
    $self->parent_broker->backend->send(
        $self,
        $destination, 
        $frame->headers, 
        $frame->body_ref,
        sub {
            # backend send success
            if ($has_receipt) {
                $self->send_client_receipt( $receipt_id );
            }
        },
        sub {
            # backend send fail
            my ($fail_reason) = @_;
            $self->send_client_error( $fail_reason, $frame );
            $self->disconnect( $fail_reason );
        },
    );
}


sub handle_frame_subscribe {
    my ($self, $frame) = @_;
    # validate subscribe frame
    # ------------------------
    # 1.0 requires 'destination'
    if (not exists $frame->headers->{'destination'}) {
        $self->send_client_error( 'SUBSCRIBE header "destination" required', $frame);
        return;
    }
    my $destination = $frame->headers->{'destination'};
    my $subscription_id = $destination; # use the destination for 1.0 clients
    if ($self->protocol_version eq '1.1') {
        # 1.1 requires 'id'
        if (not exists $frame->headers->{'id'}) {
            $self->send_client_error( 'SUBSCRIBE header "id" required', $frame);
            return;
        }
        $subscription_id = $frame->headers->{'id'};
    }
    my %opts = (
        ack         => STOMP_ACK_AUTO(),
    );
    if (exists $frame->headers->{'ack'}) {
        my $ack = $frame->headers->{'ack'} || '';
        if ($ack eq 'auto') {
            $opts{ack} = STOMP_ACK_AUTO();
        }
        elsif ($ack eq 'client') {
            $opts{ack} = STOMP_ACK_CLIENT();
        }
        elsif ($ack eq 'client-individual') {
            $opts{ack} = STOMP_ACK_INDIVIDUAL();
        }
        else {
            $self->send_client_error( 
                'Supported SUBSCRIBE header "ack" are: '.join(',', 'auto', 'client', 'client-individual'), 
                $frame,
            );
            return;
        }
    }
    my $subscription = AnyEvent::Stomp::Broker::Session::Subscription->new(
        id          => $subscription_id,
        session     => $self,
        destination => $destination,
        %opts,
    );
    weaken $self;
    # TODO: policy for repeat subscription_id
    $self->parent_broker->backend->subscribe(
        $self,
        $subscription,
        sub {
            # successful subscription
            my ($sub) = @_;
            if (exists $frame->headers->{'receipt'}) {
                my $sub_receipt_headers = { };
                if ($sub->session->protocol_version eq '1.1') {
                    $sub_receipt_headers->{'id'} = $sub->id;
                }
                $self->send_client_receipt($frame->headers->{'receipt'}, $sub_receipt_headers);
            }
        },
        sub {
            # failed subscription
            my ($fail_reason, $sub) = @_;
            $self->send_client_error($fail_reason, $frame);
            $self->disconnect( $fail_reason );
        },
    );
}


__PACKAGE__->meta->make_immutable;


1;

__END__
