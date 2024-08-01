#! /usr/bin/perl -w
use strict;

=head1 NAME

fft.pl - plot a FFT of an event list

=head1 SYNOPSIS

fft.pl [options] fitsfile

=head1 DESCRIPTION

blah blah blah

=head1 OPTIONS

=over 4

=item --help

Show help and exit.

=item --version

Show version and exit.

=item --extname=s

FITS binary extension from which event time values are taken.
Default is 'events'

=item --column=s

Name of column containing event times. Default is 'time'.

=item --filter=s

A cfitsio filter to apply.

=item --dev=s

PGPLOT device to which to plot is written. Default is '/xs'.

=item --nosubmean

Do not subtract the mean bin value from each bin.

=item --resolution=f

Light curve binning value. The default is calculated based on
the minimum non-zero time between consecutive events.

=item --power=i

Pad the light curve bin to the nearest power of the given
argument. Additional bins are set to the median value of the
original histogram.

=item --autopower

Equivalent to giving a --power argument with one of 2, 3 or 5. Whichever
comes closest to the original number of light curve bins is chosen.

=item --freq

Plot the power spectrum in frequency space, instead of the default
period space.

=item --fftw

Use the PDL::FFTW module instead of PDL::FFT.

=item --xin=f

Minimum X value to plot.

=item --xmax=f

Maximum X value to plot.

=back

=head1 AUTHOR

Pete Ratzlaff E<lt>pratzlaff@cfa.harvard.eduE<gt> June 2005

=head1 SEE ALSO

perl(1).

=cut

my $version = '0.1';

use FindBin;
use Config;
use lib '/home/rpete/local/perlmods';
use lib '/home/rpete/local/perlmods/'.$Config{archname};
use PDL;
use PDL::FFT;
use PGPLOT;
use Chandra::Tools::Common qw( read_bintbl_cols );
use Carp;

use Getopt::Long;
my %default_opts = (
		    dev => '/xs',
		    extname => 'events',
		    column => 'time',
		    submean => 1,
		    );
my %opts = %default_opts;
GetOptions(\%opts,
	   'help!', 'version!', 'dev=s', 'extname=s', 'column=s',
	   'resolution=f', 'debug!', 'fftw!',
	   'power=i', 'autopower!', 'freq!', 'xmin=f', 'xmax=f',
	   'txt!', 'interarrival!', 'submean!', 'filter=s',
	   ) or die "Try --help for more information.\n";
$opts{help} and _help();
$opts{version} and _version();

if ($opts{debug}) {
  $SIG{__WARN__} = \&Carp::cluck;
  $SIG{__DIE__} = \&Carp::confess;
}

if ($opts{fftw}) {
  eval {
    my $home = $ENV{HOME} || +(getpwuid $>)[7];
    $PDL::FFT::wisdom = "$home/.fftwisdom";
    my $jnk = $PDL::FFT::wisdom; # squelch "variable used only once" warning
    require PDL::FFTW;
    import PDL::FFTW;
#    PDL::FFTW::load_wisdom('/home/rpete/.fftwisdom');
  };
  die $@ if $@;
}

@ARGV == 1 or die "Usage: $0 [options] fitsfile\n\ttry --help for more information\n";

my ($file) = @ARGV;

my $time;
if ($opts{txt}) {
  $time = rcols $file;
}
else {
  print STDERR "reading events..."; STDERR->flush;
  ($time) = read_bintbl_cols($file, $opts{column},
			      { extname => $opts{extname}, status=>1,
				( $opts{filter} ? (rfilter =>$opts{filter} ) : () ),
			      }
			      ) or die;
  warn " done\n"; flush STDERR;
}

if ($opts{interarrival}) {
  $time = $time->cumusumover;
}
else {
  $time = $time->qsort;
}

$time->nelem > 3 or die 'only '.$time->nelem.' events found';

if (!$opts{resolution}) {
  my $time_diff = $time->mslice([1,-1]) - $time->mslice([0,-2]);
  my $index = which($time_diff > 0);
  $index->nelem or die 'no time difference > 0 found';
  $opts{resolution} = $time_diff->index($index)->min;
}

warn "using resolution = $opts{resolution}\n";

pgopen($opts{dev}) > 0 or die;

my ($tmin, $tmax) = $time->minmax;
run_fft($time, $tmin, $tmax, $opts{resolution});

pgclos();

exit 0;

sub run_fft {
  my ($time, $tmin, $tmax, $res) = @_;

  # light curve binned on time resolution
  my ($lcx, $lcy) = hist($time, $tmin, $tmax+$res, $res);
  $lcy -= $lcy->avg if $opts{submean};

  if ($opts{autopower}) {
    my $diff = -1;
    my $power;
    for (2,3,5) {
      my $nelem = _nextpow($_, $lcy->nelem);
      if ( ($diff < 0) or
	   $nelem - $lcy->nelem < $diff) {
	$diff = $nelem - $lcy->nelem;
	$power = $_;
      }
    }
    warn "--autopower chose power=$power\n";
    $opts{power} = $power;
  }

  if ($opts{power}) {
    my $num = _nextpow($opts{power}, $lcy->nelem);
    my $tmpy = zeroes($lcy->type, $num);
    (my $tmp = $tmpy->mslice([0,$lcy->nelem-1])) .= $lcy;
    # fill in the rest of the light curve with the median value
#    ($tmp = $tmpy->mslice([$lcy->nelem-2,-1])) .= +($lcy->stats)[2];
    $lcy = $tmpy;
  }

  warn "FFT on light curve with ".$time->nelem." events in ".$lcy->nelem." bins\n";

  my $fft;
  if ($opts{fftw}) {
    $fft = fftw(cat($lcy, zeroes($lcy->type, $lcy->nelem))->transpose);
  }
  else {
    my $fftr = $lcy->copy;
    my $ffti = zeroes($fftr->type, $fftr->nelem);
    fft($fftr, $ffti);
    $fft = cat($fftr, $ffti)->transpose;
  }

  # power spectrum procedure taken from
  # http://www.mathworks.com/support/tech-notes/1700/1702.html

  $fft = $fft->mslice([0,1],[0,int($lcy->nelem/2)]);

#  my $psd = sqrt($fft->slice('(0),')**2 + $fft->slice('(1),')**2) / $lcy->nelem * 2;
  my $psd = ($fft->slice('(0),')**2 + $fft->slice('(1),')**2) / $time->nelem * 2;

  my $freq = (sequence($psd->nelem)+1) / $lcy->nelem / $res;
  my $period = 1/$freq;

  $psd->set(0, $psd->at(0)/2);
  $psd->set(-1, $psd->at(-1)/2) unless $psd->nelem % 2;
  $_ = $_->mslice([1,-1]) for $psd, $period, $freq; # omit DC component

  for my $c (0.10, 0.01, 0.001) {
    my $pdet = 2*log($psd->nelem /2) + 2*log(1/(1-$c));
    my $n = which($psd>$pdet)->nelem;
    print "P_detect (C = $c) = $pdet ($n bins qualify)\n";
  }

  my $maxi = $psd->maximum_ind + 1; # since we sliced off the first element of $psd earlier
  print "maximum power = ".$psd->at($maxi)." in bin $maxi of ".($psd->nelem+1)."\n";

  my $xvals = $opts{freq} ? $freq : $period;

  my ($xmin, $xmax) = (exists $opts{xmin} ? $opts{xmin} : $xvals->min,
	  exists $opts{xmax} ? $opts{xmax} : $xvals->max);

  my $i = which(($xvals>=$xmin) & ($xvals<=$xmax));
  $_ = $_->index($i) for $psd, $xvals;
  my ($ymin, $ymax) = (
		       $psd->min - ($psd->max - $psd->min) * .1,
		       $psd->max + ($psd->max - $psd->min) * .1,
		      );

  if (!$opts{freq}) {
    $_ = log10($_) for $xmin, $xmax, $xvals;
  }
  pgenv($xmin, $xmax, $ymin, $ymax, 0, $opts{freq} ? 0 : 10);
  pgline($psd->nelem,
	 ($opts{freq} ?
	  $freq->float->get_dataref :
	  $xvals->float->get_dataref
	 ),
	 $psd->float->get_dataref);
  pgsci(1);

  pglabel(
	  (
	   $opts{freq} ?
	   'Frequency (Hz)' :
	   'Period (s)'
	  ),
	  'FFT power',
	  $file
	  );

}

sub _help {
  exec("$Config{installbin}/perldoc", '-F', $FindBin::Bin . '/' . $FindBin::RealScript);
}

sub _version {
  print $version,"\n";
  exit 0;
}

sub _nextpow {
  my ($n, $i) = @_;
  my $logn = log($i) / log($n); # $n-base log of $i

  my $retval = $n;
  for (1..$logn) {
    return $retval if $retval == $i;
    $retval *= $n;
  }
  return $retval;
}
