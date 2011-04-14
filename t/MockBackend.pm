package MockBackend;
use strict;
use Moose;
with 'AnyEvent::Stomp::Broker::Role::Backend';

has 'queue' => ( is => 'rw', isa => 'ArrayRef', default => sub { [ ] } );

# observer callbacks
has 'send_obs'          => ( is => 'rw', isa => 'CodeRef', lazy => 1, default => sub { sub { } } );
has 'subscribe_obs'     => ( is => 'rw', isa => 'CodeRef', lazy => 1, default => sub { sub { } } );


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
        $success_cb->($sub);
    }
    else {
        $fail_cb->('backend subscribe simulated fail', $sub);
    }
}

sub mock_enqueue {
    my ($self, $mock_message) = @_;
    push @{$self->queue}, $mock_message;
}


__PACKAGE__->meta->make_immutable;

1;

__END__
