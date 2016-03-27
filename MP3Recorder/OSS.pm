package MP3Recorder::OSS;

use strict;
use warnings;

use Audio::OSS qw(:funcs :formats SNDCTL_DSP_GETBLKSIZE SNDCTL_DSP_SETTRIGGER);
use IO::File;
use Event;
use Event::IOExtra;
use Time::HiRes;

=head1 NAME

MP3Recorder::OSS - the mp3recorder component for OSS soundcards

=head1 DESCRIPTION

This will be developed to be a uniform interface for soundcard drivers, and a specific implementation for OSS.

=head1 METHODS

=over

=item B<new> - constructor

see the method B<setup> for parameters

=cut

sub new {
    my $proto=shift;
    my $class=ref($proto)||$proto;
    my $self=+{
        dev=>'/dev/dsp',
        sr=>44100,
        numchannels=>2,
    };
    bless($self,$class);
    $self->setup(@_);
    return $self;
}

=item B<setup> sets up the sound device

parameters:

=over

=item device

=item sample_rate

=item num_channels

=item user_cb
code ref, this will be called with recorded data

=item user_data
this will be passed as first arg

=back

=cut
sub setup {
    my $self=shift;
    my %arg=@_;
    my $argmap=+{
        'dev'=>'device',
        'sr'=>'sample_rate',
        'numchannels'=>'num_channels',
        'user_cb'=>'user_cb',
        'user_data'=>'user_data'
    };
    for my $p (keys %$argmap) {
        $self->{$p}=$arg{$argmap->{$p}} if defined $arg{$argmap->{$p}};
    }
}

=item B<start_record>

Starts recording. Creates the Even watcher, and starts the device.

=cut

sub start_record {
    my $self=shift;
    $self->open_device;
    $self->setup_device;
    my $fh=$self->{fh};
    
    # now $self->{bsize} is set up
    my $dspcom=Event::IOExtra->new(
        'user'=>$self,
        'user_cb'=>\&handle_read,
        'poll'=>'r',
        'fd'=>$fh,
        'blocksize'=>$self->{bsize}
    );
    $self->{dspcom}=$dspcom;
    my $out=0;
    ioctl($fh, SNDCTL_DSP_SETTRIGGER, $out) or return undef;
}

sub stop_record {
    my $self=shift;
    $self->{stop}=1;
}

# this is called by Event::IOExtra
sub handle_read {
    my $self=shift;
    my $dataref=shift;
    # my ($frags,$fragstotal,$fragsize,$avail)=get_inbuf_info($self->{fh});
    # print STDERR "Fragments still in driver/hw: $frags / $fragstotal, bytes readable: $avail\n";
    if ($self->{stop}) {
        $self->{dspcom}->cancel;
        delete $self->{dspcom};
        close $self->{fh};
        $self->{user_cb}->($self->{user_data},undef);
        return;
    }
    $self->{user_cb}->($self->{user_data},$dataref);
}

sub open_device {
    my $self=shift;
    my $fh=$self->{fh}=IO::File->new;
    $fh->open($self->{dev},'<')  or die "$self->{dev}: $!";
    # dsp_reset($self->{fh});         # this is bullshit, OSS API docs says don't use this unless needed
    set_fragment($fh,16,8);

}

sub setup_device {
    my $self=shift;
    my $fh=$self->{fh};
    my $mask=get_supported_fmts($fh);
    
    my $stereo=$self->{numchannels};
    die "only mono and stereo supported" unless $stereo<=2 and $stereo>=1;
    $stereo--;
    my $gotstereo=set_stereo($fh,$stereo);
    die "$self->{dev}: could not set stereo($stereo -> $gotstereo)" if $gotstereo!=$stereo;
    
    if ($mask & AFMT_S16_LE) {
        set_fmt($fh,AFMT_S16_LE) or die "$self->{dev}: setting format failed: $!";
    } else {die "$self->{dev} does not support mandatory format AFMT_S16_LE";}
    my $sr=set_sps($fh,$self->{sr});
    if (abs($sr-$self->{sr})>=($self->{sr}*0.01)) {
        # the real samplerate differs from the requested by more than 1%
        # we are already very generous, imho
        die "$self->{dev} gave samplerate $sr instead of $self->{sr}";
    }
    
    my $bsize=$self->get_blocksize;
    $self->{bsize}=$bsize;
    my ($frags,$fragstotal,$fragsize,$avail)=get_inbuf_info($self->{fh});
    print STDERR "bsize: $bsize, fragments: $fragstotal, fragment size: $fragsize\n";
}

sub get_blocksize {
    my $self=shift;
    my $fh = $self->{fh};
    my $in = 0;
    my $out = pack "L", $in;
    ioctl($fh, SNDCTL_DSP_GETBLKSIZE, $out) or return undef;
    return unpack "L", $out;
}

sub get_bufinfo {
    my $self=shift;
    my $most=Time::HiRes::gettimeofday();
    my (undef,undef,undef,$avail)=get_inbuf_info($self->{fh});
    return ($most,$avail);
}

=back

=cut

1;
