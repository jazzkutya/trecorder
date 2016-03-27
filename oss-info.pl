#!/usr/bin/perl

use Audio::OSS qw(:funcs :formats :caps SNDCTL_DSP_GETBLKSIZE SNDCTL_DSP_SETTRIGGER);
use IO::File;

my $dev='/dev/dsp';

my $dsp=IO::File->new();
$dsp->open($dev,'<') or die "$dev: $!";
set_fragment($dsp,20,8);

print "This program will try to analyze your soundcard/driver capabilities\n";
capabilities($dsp);
formats($dsp);

set_fmt($dsp,AFMT_S16_LE);
die "I'm a bitch, I don't like this card!" unless set_fmt($dsp,AFMT_QUERY)==AFMT_S16_LE;
die "I'm a bitch, I don't like this card!" unless set_stereo($dsp,1)==1;
my $sr=set_sps($dsp,44100);
print "Sample rate is $sr\n";

my $bsize=get_blocksize($dsp);
my ($frags,$fragstotal,$fragsize,$avail)=get_inbuf_info($dsp);
print "bsize: $bsize, fragments: $fragstotal, fragment size: $fragsize\n";

my $data;
sysread($dsp,$data,$bsize);
my ($oldavail)=(0);
my $d;
while (1) {
    (undef,undef,undef,$avail)=get_inbuf_info($dsp);
    if ($avail>=$bsize) {
        my $read=sysread($dsp,$data,$bsize);
        (undef,undef,undef,$avail)=get_inbuf_info($dsp);
    }
    $d=$avail-$oldavail;
    if ($d>(1764*1) ) {
        print "$d\n";
    }
    $oldavail=$avail;
}

sub capabilities {
    print "\nOSS Capabilities:\n";
    my $dsp=shift;
    my $caps=dsp_get_caps($dsp);
    my $rev=$caps & DSP_CAP_REVISION;
    my $capmap=+{
        DSP_CAP_DUPLEX()=>'Full duplex',
        DSP_CAP_REALTIME()=>'Realtime pointer information',
        DSP_CAP_BATCH()=>'Batch',
        DSP_CAP_COPROC()=>'Has DSP (do not trust this info)',
        DSP_CAP_TRIGGER()=>'Can trigger',
        DSP_CAP_MMAP()=>'Direct access'
    };
    my @caps=sort keys %$capmap;
    print "get_caps revision: $rev\n";
    for my $cap (@caps) {
        my $result=($caps & $cap)?'Yes':'no';
        my $capname=$capmap->{$cap};
        print "$capname: $result\n";
    }
}

sub formats {
    print "\nSupported formats:\n";
    my $dsp=shift;
    my $formats=get_supported_fmts($dsp);
    my $formatmap=+{
        AFMT_S16_NE()=>'S16 NE',
        AFMT_S16_LE()=>'S16 LE',
        AFMT_S16_BE()=>'S16 BE',
        AFMT_U16_LE()=>'U16 LE',
        AFMT_U16_BE()=>'U16 BE',
        AFMT_U8()=>'U8',
        AFMT_MU_LAW()=>'Mu-Law',
        AFMT_A_LAW()=>'A-Law'
    };
    my @formats=sort keys %$formatmap;
    for my $format (@formats) {
        my $result=($formats & $format)?'Yes':'no';
        my $formatname=$formatmap->{$format};
        print "$formatname: $result\n";
    }
}

sub get_blocksize {
    my $fh = shift;
    my $in = 0;
    my $out = pack "L", $in;
    ioctl($fh, SNDCTL_DSP_GETBLKSIZE, $out) or return undef;
    return unpack "L", $out;
}
