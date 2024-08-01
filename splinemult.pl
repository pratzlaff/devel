#! /usr/bin/perl -w
use strict;

=head1 NAME

template - A template for Perl programs.

=head1 SYNOPSIS

cp template newprog

=head1 DESCRIPTION

blah blah blah

=head1 OPTIONS

=over 4

=item --help

Show help and exit.

=item --version

Show version and exit.

=back

=head1 AUTHOR

Pete Ratzlaff E<lt>pratzlaff@cfa.harvard.eduE<gt> March 2011

=head1 SEE ALSO

perl(1).

=cut

my $version = '0.1';

use FindBin;
use Config;
use Carp;
use Astro::FITS::CFITSIO;
use Chandra::Tools::Common qw( read_bintbl_cols );
use File::Copy;
use PDL;
use PDL::IO::Misc;

use Getopt::Long;
my %default_opts = (

		    infile => '/data/legs/rpete/flight/extraction_efficiency/letgD1996-11-01greffpr001N0006.fits',
		    outfile => 'letgD1996-11-01greffpr001N0007.fits',
		    splineout => '/data/legs/rpete/flight/extraction_efficiency/splineout',
		    );
my %opts = %default_opts;
GetOptions(\%opts,
	   'help!', 'version!', 'debug!',
	   'infile=s', 'outfile=s', 'splineout=s',
	   ) or die "Try --help for more information.\n";
if ($opts{debug}) {
  $SIG{__WARN__} = \&Carp::cluck;
  $SIG{__DIE__} = \&Carp::confess;
}
$opts{help} and _help();
$opts{version} and _version();

copy($opts{infile}, $opts{outfile}) or die $!;

my $s = 0;
my $fptr = Astro::FITS::CFITSIO::open_file($opts{outfile}, Astro::FITS::CFITSIO::READWRITE(), $s);
$fptr->write_date($s);
$fptr->write_chksum($s);

my @files = sort { $b cmp $a } glob($opts{splineout} . '/*.out');

my @orders = 1..25;
@orders = (reverse(@orders), 0, @orders);


for my $hdrnum (2..5) {

  $fptr->movabs_hdu($hdrnum, Astro::FITS::CFITSIO::BINARY_TBL(), $s);
  $fptr->write_date($s);

  my ($o4eff);

  my ($eff) = read_bintbl_cols($fptr, 'eff');

  for my $f (@files) {
    $f =~ /spline(\d+).out/;
    my $o = $1 or next;

    print "got $f: order $o\n";

    my ($e, $mult) = rcols $f, 0, 2;

    my @i = grep { $orders[$_] == $o } 0..$#orders;

    my $tmp;
    for my $i (@i) {

      ($tmp = $eff->slice("($i)")) *= $mult;

      if ($o==4 and !defined($o4eff)) {
	$o4eff = $eff->slice("($i)");
      }

      if ($o == 2) {
	my $ii = which($e < 0.413);
	(my $tmp = $eff->slice("($i)")->index($ii)) .= 1.392 * $o4eff->index($ii);
      }
    }


  }

  $fptr->write_col(Astro::FITS::CFITSIO::TDOUBLE(), 2, 1, 1, $eff->nelem, $eff->double->get_dataref, $s);

  $fptr->write_date($s);
  $fptr->write_chksum($s);

  check_status($s);

}

$fptr->close_file($s);

exit 0;

sub _help {
  exec("$Config{installbin}/perldoc", '-F', $FindBin::Bin . '/' . $FindBin::RealScript);
}

sub _version {
  print $version,"\n";
  exit 0;
}

sub check_status {
  my $s = shift;
  if ($s != 0) {
    my $txt;
    Astro::FITS::CFITSIO::fits_get_errstatus($s,$txt);
    carp "CFITSIO error: $txt";
    return 0;
  }

  return 1;
}
