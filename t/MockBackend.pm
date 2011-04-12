package MockBackend;
use Moose;
with 'AnyEvent::Stomp::Broker::Backend';

has 'send_cb' => ( is => 'rw', isa => 'CodeRef', lazy => 1, default => sub { sub { } } );

sub send { return $_[0]->send_cb->(@_); }

1;

__END__
