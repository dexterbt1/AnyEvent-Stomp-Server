package AnyEvent::Stomp::Server::Frame;
use strict;
use Any::Moose;
use Scalar::Util qw/weaken/;
our $CRLF = "\n";
no warnings 'uninitialized';

has 'command' => (is => 'rw', isa => 'Str');
has 'headers' => (is => 'rw', isa => 'HashRef', lazy => 1, default => sub { {} });
has 'body_ref' => (is => 'rw', isa => 'Ref');

sub body_as_string { 
    my $b_ref = $_[0]->body_ref;
    ref($b_ref) ? $$b_ref : '';
}

sub as_string {
    my ($self) = @_;

    my $out = '';
    $out .= $self->{command}.$CRLF;

    my $b_ref = $self->{body_ref};
    my $body_str = ref($b_ref) ? $$b_ref : ''; # inline impl

    my %h = %{$self->{headers}};
    $h{'content-length'} = length($body_str);
    foreach (sort keys %h) {
        my ($k, $v) = ($_, $h{$_});
        $out .= _encode_header_value($k).":"._encode_header_value($v).$CRLF;
        #$out .= "$k:$v$CRLF";
    }
    $out .= $CRLF;

    $out .= $body_str."\000",

    return $out;
}

sub anyevent_read_type {
    my ($handle, $cb) = @_;
    return sub {
        $_[0]{rbuf} =~ s/^(.*?)(\015\012\015\012|\012\012)//s
            or return 0; # no data yet
        my $raw_headers = $1;
        my $command;
        
        my $headers = { };
        foreach my $line (split /\015\012|\012/, $raw_headers) {
            next if ($line eq ''); # ignore black lines; probably keep-alives
            if (not defined $command) {
                $command = $line;
                next;
            }
            my ($k, $v) = split /:/, $line, 2;
            _decode_header_value($k);
            _decode_header_value($v);
            $headers->{$k} = $v;
        }
        my @args = ('regex' => qr/.*?\000\n*/s);
        if (my $content_length = $headers->{'content-length'}) {
            @args = ('chunk' => $content_length + 1);
        }
        my $body;
        ## print STDERR "commands+headers read ...\n";
        $_[0]->push_read(@args, sub { 
            $body = $_[1];
            $body =~ s/\000\n*$//;
            # callback w/ the frame
            my $frame = __PACKAGE__->new( command => $command, headers => $headers, body_ref => \$body );
            $cb->( $_[0], $frame );
            ## print STDERR "body read ...\n";
        });
        return 1;
    };
}

# functions

sub _headers_as_string {
    my $h = $_[0];
    return join($CRLF, 
        map { 
            my $x = $_;
            sprintf(
                "%s:%s",
                _encode_header_value($_),
                _encode_header_value($h->{$x})
            ) 
        } sort keys %$h
    );
}

sub _encode_header_value {
    # mutator
    return $_[0] if (not $_[0]=~/[\\\n:]/);
    $_[0] =~ s/\\/\\\\/g;
    $_[0] =~ s/\n/\\n/g;
    $_[0] =~ s/:/\\c/g;
    $_[0];
}

sub _decode_header_value {
    # mutator
    $_[0] =~ s/\\n/\n/g;
    $_[0] =~ s/\\c/:/g;
    $_[0] =~ s/\\\\/\\/g;
    $_[0];
}

__PACKAGE__->meta->make_immutable;

1;

__END__
