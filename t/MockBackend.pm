package MockBackend;
use strict;
use Moose;
with 'AnyEvent::Stomp::Broker::Role::Backend';

has 'queue' => ( is => 'rw', isa => 'ArrayRef', default => sub { [ ] } );

# observer callbacks
has 'send_obs'          => ( is => 'rw', isa => 'CodeRef', lazy => 1, default => sub { sub { } } );
has 'subscribe_obs'     => ( is => 'rw', isa => 'CodeRef', lazy => 1, default => sub { sub { } } );
has 'disconnect_obs'    => ( is => 'rw', isa => 'CodeRef', lazy => 1, default => sub { sub { } } );

has 'subscriptions'     => ( is => 'rw', isa => 'HashRef[Str]', lazy => 1, default => sub { { } } );


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
            $self->subscriptions->{$sub->destination} = [ ];
        }
        push @{$self->subscriptions->{$sub->destination}}, $sub;
        $success_cb->($sub);
    }
    else {
        $fail_cb->('backend subscribe simulated fail', $sub);
    }
}

sub inject_message {
    my ($self, $dest, $body_ref, $headers) = @_;
    push @{$self->queue}, [ $dest, $body_ref, $headers ];
}


sub on_session_disconnect {
    my ($self, $sess) = @_;
    $self->disconnect_obs->(@_);
}


__PACKAGE__->meta->make_immutable;

1;

__END__
