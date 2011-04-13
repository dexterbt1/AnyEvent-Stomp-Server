package MockBackend;
use strict;
use Moose;
with 'AnyEvent::Stomp::Broker::Backend';

has 'queue' => ( is => 'rw', isa => 'ArrayRef', default => sub { [ ] } );

# observer callbacks
has 'send_obs'          => ( is => 'rw', isa => 'CodeRef', lazy => 1, default => sub { sub { } } );
has 'subscribe_obs'     => ( is => 'rw', isa => 'CodeRef', lazy => 1, default => sub { sub { } } );


sub send { 
    $_[0]->send_obs->(@_); 
}

sub subscribe { 
    my ($self, $sub, $success_cb, $fail_cb) = @_;
    $self->subscribe_obs->(@_); 
    if ($success_cb) {
        $success_cb->($sub);
    }
}

sub mock_enqueue {
    my ($self, $mock_message) = @_;
    push @{$self->queue}, $mock_message;
}

1;

__END__
