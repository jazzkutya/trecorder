package Event::IOExtra;

use Event;
use Event::io;
use base 'Event::io';

our $buf_threshold_default=1024*1024;
1;

=begin history
call $self->{user_cb}->($self->{user}) instead of $self->{user}->handle_read
optional new parameter: blocksize
optional new parameter: $buf_threshold, but is is a class variable!!!!
=cut
sub new {
    my $p=shift;
    my %p=@_;
    my $user=delete $p{user};
    my $user_cb=delete $p{user_cb};
    my $parked=delete $p{parked};
    my $bsize=delete($p{blocksize}) || 1024;
    my $bthres=delete($p{buffer_size}) || $buf_threshold_default;
    my $self=$p->SUPER::new(
        'parked'=>1,
        %p
    );
    $self->cb([$self,'eventhandler']);
    $self->private(+{
            'user'=>$user,
            'user_cb'=>$user_cb,
            'outbuf'=>'',
            'outbufp'=>0,
            'bsize'=>$bsize,
            'bthres'=>$bthres
        });
    $self->start unless $parked;
    return $self;
}

sub eventhandler {
    my $self=shift;
    my $p=$self->private();
    my $event=shift;
    my $got=$event->got();
    my $w=$event->w();
    my $fd=$w->fd();
    my $buffer='';
    if ($got=~/r/i) {
        # handle reads
        TRY: while (1) {
            my $retval=sysread($fd,$buffer,$p->{bsize});
            if (!defined($retval)) {
                next TRY if $!{EINTR};                      # re-do the read if it was interrupted by a signal
                last if $!{EAGAIN};                         # do nothing if nothing yet
                # TODO: handle other errors
                die "$!";
                last;
            }
            if ($retval==0) {
                # mit csinaljunk eof-nal????
                $buffer='';
                if ($p->{user_cb}) {
                    $p->{user_cb}->($p->{user},\$buffer);
                } else {
                    $p->{user}->handle_read(\$buffer);
                }
                $self->want_read(0);
            } else {
                if ($p->{user_cb}) {
                    $p->{user_cb}->($p->{user},\$buffer);
                } else {
                    $p->{user}->handle_read(\$buffer);
                }
            }
            last;
        }
    }
    if ($got=~/w/i) {
        # handle writes
        if (!length($p->{outbuf})) {
            if ($p->{do_close}) {
                $self->cancel;
            } else {$self->want_write(0);};
        } else {
            my $length=length($p->{outbuf})-$p->{outbufp};
            $length = $p->{bsize} if $length > $p->{bsize};
            # try this
            TRY: while (1) {
                my $retval=syswrite($fd,$p->{outbuf},$length,$outbufp);
                if (!defined($retval)) {
                    next TRY if $!{EINTR};                      # re-do the read if it was interrupted by a signal
                    last if $!{EAGAIN};                         # do nothing if nothing yet
                    if ($!{EPIPE}) {
                        # TODO: other end closed connection...
                        $self->want_write(0);
                        last;
                    }
                    # TODO: handle other errors
                    die "$!";
                    last;
                }
                $outbufp+=$retval;
                if ($outbufp >= length($p->{outbuf})) {
                    $p->{outbuf}='';
                    $outbufp=0;
                    $self->want_write(0);
                }
                last;
            }
        }
    }
}

sub write {
    my $self=shift;
    my $p=$self->private();
    my $in=shift;
    if (!defined($in)) {
        # close the fd if everything is written
        $p->{do_close}=1;
        $self->want_write(1);
        return;
    }
    my $dataref=ref($in)?$in:\($in);
    $self->want_write(1);
    return unless $dataref;
    return unless length($$dataref);
    $p->{outbuf}.=$$dataref;
    if ( (length($p->{outbuf}) >= $p->{bthres}) && $p->{outbufp} ) {
        $p->{outbuf}=substr($p->{outbuf},$p->{outbufp});
        $p->{outbufp}=0;
    }
}

sub used_buffer {
    my $self=shift;
    my $p=$self->private();
    return length($p->{outbuf});
}

sub want_read {
    my ($self,$do)=@_;
    my $poll=$self->poll;
    return if ($poll=~s/r//gi) && $do;
    $poll.='r' if $do;
    $self->poll($poll);
}

sub want_write {
    my ($self,$do)=@_;
    my $fd=fileno $self->fd;
    my $poll=$self->poll;
    my $what=$do?'enabled':'disabled';
    return if ($poll=~s/w//gi) && $do;
    $poll.='w' if $do;
    $self->poll($poll);
    $self->start if $do;
}

