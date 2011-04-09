package AnyEvent::Stomp::Broker::Protocol::Stomp1_0;
use strict;
use Moose;
use Net::Stomp::Frame;
use Scalar::Util qw/refaddr/;

has 'parent_session' => ( is => 'rw', isa => 'AnyEvent::Stomp::Broker::Session', weak_ref => 1 );

sub connect {
    my ($self, $frame) = @_;
    my $response_frame = Net::Stomp::Frame->new({
        command => 'CONNECTED',
        headers => {
            "session-id"    => refaddr($self->parent_session),
            "version"       => $self->protocol_version,
            "server"        => ref($self->parent_session->parent_broker),
        },
        body => '',
    });
    $self->parent_session->send_client_frame( $response_frame );
    $self->parent_session->is_connected( 1 );
}

sub protocol_version {
    '1.0'
}

1;

__END__
