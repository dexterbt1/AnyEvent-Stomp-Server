package MockBackend;
use Moose;
with 'AnyEvent::Stomp::Broker::Backend';

has 'queue' => ( is => 'rw', isa => 'ArrayRef', default => sub { [ ] } );

# client initiated frames
has 'send_cb'           => ( is => 'rw', isa => 'CodeRef', lazy => 1, default => sub { sub { } } );
has 'subscribe_cb'      => ( is => 'rw', isa => 'CodeRef', lazy => 1, default => sub { sub { } } );


sub send { return $_[0]->send_cb->(@_); }
sub subscribe { return $_[0]->subscribe_cb->(@_); }

sub mock_enqueue {
    my ($self, $mock_message) = @_;
    push @{$self->queue}, $mock_message;
}

1;

__END__
