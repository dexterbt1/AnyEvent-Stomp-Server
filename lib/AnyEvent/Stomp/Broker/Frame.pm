package AnyEvent::Stomp::Broker::Frame;
use strict;
use Net::Stomp::Frame;

sub anyevent_read_type {
    my ($handle, $cb) = @_;
    
    return sub {
        $handle->push_read( 
            regex => qr/.*?\015\012\015\012|\012\012/s, 
            sub { 
                my $command;
                my $raw_headers = $_[1];
                $raw_headers =~ s[^(\015\012|\012)][]g;
                my $headers = { };
                foreach my $line (split /\015\012|\012/, $raw_headers) {
                    if (not defined $command) {
                        $command = $line;
                        next;
                    }
                    my ($k, $v) = split /:/, $line, 2;
                    $headers->{$k} = $v;
                }
                my @args = ('regex' => qr/.*?\000\n*/s);
                if (my $content_length = $headers->{'content-length'}) {
                    @args = ('chunk' => $content_length + 1);
                }
                my $body;
                $handle->push_read(@args, sub { 
                    $body = $_[1];
                    $body =~ s/\000\n*$//;
                    # callback w/ the frame
                    my $frame = Net::Stomp::Frame->new({ command => $command, headers => $headers, body => $body });
                    $cb->( $_[0], $frame );
                });
                return 1;
            },
        );
        return 1;
    };
}

1;

__END__
