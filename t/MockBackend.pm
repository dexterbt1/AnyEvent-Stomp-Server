package MockBackend;
use strict;
use Moose;
with 'AnyEvent::Stomp::Broker::Role::Backend';
use Data::UUID;
my $data_uuid = Data::UUID->new;

has 'queue'             => ( is => 'rw', isa => 'HashRef[Str]', lazy => 1, default => sub { { } } );
has 'queued_count'      => ( is => 'rw', isa => 'Int', default => sub { 0 } );

# observer callbacks
has 'send_obs'          => ( is => 'rw', isa => 'CodeRef', lazy => 1, default => sub { sub { } } );
has 'subscribe_obs'     => ( is => 'rw', isa => 'CodeRef', lazy => 1, default => sub { sub { } } );
has 'disconnect_obs'    => ( is => 'rw', isa => 'CodeRef', lazy => 1, default => sub { sub { } } );
has 'ack_obs'           => ( is => 'rw', isa => 'CodeRef', lazy => 1, default => sub { sub { } } );

# message management
has 'subscriptions'             => ( is => 'rw', isa => 'HashRef[Str]', lazy => 1, default => sub { { } } );
    # { 
    #   dest => { 
    #       "$sub_obj" => $sub,
    #       ... 
    #   }, 
    #   ... 
    # }

has 'session_subscriptions'     => ( is => 'rw', isa => 'HashRef[Str]', lazy => 1, default => sub { { } } );
    # { 
    #   sess_id => { 
    #       "$sub_obj" => $sub,
    #       ... 
    #   }, 
    #   ... 
    # }

has 'pending_messages'          => ( is => 'rw', isa => 'HashRef[Str]', lazy => 1, default => sub { { } } );
    # { 
    #   sess_id => { 
    #       msg_id => [ $sub, $msg_id, $dest, $body_ref, $headers ], 
    #       ... 
    #   }, 
    #   ... 
    # }


sub send { 
    my ($self, $destination, $headers, $body_ref, $success_cb, $fail_cb) = @_;
    if ($self->send_obs->(@_)) {
        $success_cb->();
    }
    else {
        $fail_cb->('backend send simulated fail');
    }
}

sub subscribe { 
    my ($self, $sub, $success_cb, $fail_cb) = @_;
    if ($self->subscribe_obs->(@_)) {
        if (not exists $self->subscriptions->{$sub->destination}) {
            $self->subscriptions->{$sub->destination} = { }
        }
        $self->subscriptions->{$sub->destination}->{"$sub"} = $sub;

        if (not exists $self->session_subscriptions->{$sub->session->session_id}) {
            $self->session_subscriptions->{$sub->session->session_id} = { };
        }
        $self->session_subscriptions->{$sub->session->session_id}->{"$sub"} = $sub;
        $success_cb->($sub);
    }
    else {
        $fail_cb->('backend subscribe simulated fail', $sub);
    }
}

# simulated
sub inject_message {
    my ($self, $dest, $body_ref, $headers) = @_;
    my $msg_id = $data_uuid->create_str;
    my $raw_message = [ $dest, $body_ref, $headers ];
    # hint dispatch
    $self->dispatch_message( $msg_id => $raw_message );
}

sub dispatch_message {
    my ($self, $msg_id, $raw_message) = @_;

    my $dest_subscriptions = $self->subscriptions->{$raw_message->[0]} || { };
    my @dest_subscriptions_keys = keys %$dest_subscriptions;
    return if (scalar @dest_subscriptions_keys <= 0);

    # find suitable subscription, randomly
    my $rand_key = int(rand(scalar @dest_subscriptions_keys));
    my $sub = $dest_subscriptions->{$dest_subscriptions_keys[$rand_key]};
    return if (not defined $sub);

    # send MESSAGE frame
    $self->pending_messages->{$sub->session->session_id}->{$msg_id} = [ $sub, $msg_id, @$raw_message ];
    $sub->session->send_client_message( $sub, $msg_id, @$raw_message );
    # wait for ack, on a different event
    # TODO timeout
}


sub ack {
    my ($self, $session, $msg_id, $success_cb, $failure_cb) = @_;
    if ($self->ack_obs->(@_)) {
        my $t = delete $self->pending_messages->{$session->session_id}->{$msg_id};
        $success_cb->($session, $msg_id);
    }
    else {
        $failure_cb->("simulated ack failure", $session, $msg_id);
    }
    
}


sub on_session_disconnect {
    my ($self, $sess) = @_;
    $self->disconnect_obs->(@_);

    # cleanup subscriptions
    my $sess_subscriptions = delete $self->session_subscriptions->{$sess->session_id};
    if ($sess_subscriptions) {
        foreach my $sub_id (keys %$sess_subscriptions) {
            my $sub = $sess_subscriptions->{$sub_id};
            delete $self->subscriptions->{$sub->destination}->{$sub_id};
        }
    }

    # cleanup pending messages

    my $pending_messages = delete $self->pending_messages->{$sess->session_id};
    if ($pending_messages) {
        foreach my $msg_id (keys %$pending_messages) {
            my $pm = $pending_messages->{$msg_id};
            next if (not defined $pm);
            # remove the subscription
            delete $self->subscriptions->{sprintf("%s",$pm->[1])};
            # ALSO, a real backend should somehow re-enqueue the messages left by the disconnected client
        }
    }
}


__PACKAGE__->meta->make_immutable;

1;

__END__
