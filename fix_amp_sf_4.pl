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

Show version and exit;

=back

=head1 AUTHOR

Pete Ratzlaff E<lt>pratzlaff@cfa.harvard.eduE<gt> March 2002

=head1 SEE ALSO

perl(1).

=cut

my $version = '0.1';

use FindBin;
use Astro::FITS::CFITSIO qw(  fits_report_error fits_str2time READONLY BINARY_TBL );
use Time::Local;

use Getopt::Long;
my %default_opts = (
		    );
my %opts = %default_opts;
GetOptions(\%opts,
	   'help!', 'version!',
	   ) or die "Try --help for more information.\n";
$opts{help} and _help();
$opts{version} and _version();

@ARGV==2 or
  die "invalid arguments\nTry --help for more information.\n";

my ($in, $out) = @ARGV;

my $status = 0;
my $fptr = Astro::FITS::CFITSIO::open_file($in, READONLY, $status)
  or status_err($status);
$fptr->movnam_hdu(BINARY_TBL, 'EVENTS', 0, $status);
status_err($status);

my $hdr = $fptr->read_header;
exists $hdr->{DETNAM} and exists $hdr->{'DATE-OBS'} or
  die "DETNAM or DATE-OBS does not exist in EVENTS HDU";

$hdr->{$_} =~ s/^'(.*)\s*'$/$1/ for qw( DETNAM DATE-OBS );

my ($year, $month, $day);
fits_str2time($hdr->{'DATE-OBS'}, $year, $month, $day,
	      undef, undef, undef, $status) and status_err($status);

# changed 1999-12-06
my $range_switch =
  timelocal(0,0,0,$day,$month-1,$year-1900)<timelocal(0,0,0,6,12-1,1999-1900) ?
  90 :
  $hdr->{DETNAM} =~ /HRC-I/ ? 115 :
  $hdr->{DETNAM} =~ /HRC-S/ ? 125 :
  die "DETNAM=$hdr->{DETNAM} not handled";

my @fix_amp_sf_args = ('-i', $in, '-o', $out);
for ($hdr->{DETNAM}) {
  if (/HRC-I/) {
    if ($range_switch == 90) {
      push @fix_amp_sf_args, '-p50.5', '-P99.0';
    }
    elsif ($range_switch == 115) {
      push @fix_amp_sf_args, '-p64.5', '-P126.5';
    }
    else { die }
    last;
  }
  elsif (/HRC-S/) {
    push @fix_amp_sf_args, qw( -g52.9 -a250 -b250 -c250 -t5.0 -T5.0 );
    if ($range_switch == 90) {
      push @fix_amp_sf_args, '-p51.0', '-P99.5';
    }
    elsif ($range_switch == 125) {
      push @fix_amp_sf_args, '-p70.5', '-P137.5';
    }
    else { die }
    last;
  }
  else { die }
}

my $fix_amp_sf_path =
  $^O eq 'linux' ? '/data/legs/rpete/flight/dev/fix_amp_sf_4_linux' :
  $^O eq 'solaris' ? '/data/legs/rpete/flight/dev/fix_amp_sf_4_solaris' :
  die "no fix_amp_sf binary for $^O";


print join ' ', $fix_amp_sf_path, map "'$_'", @fix_amp_sf_args;
print "\n";
exit exec $fix_amp_sf_path, @fix_amp_sf_args;


exit 0;

sub status_err {
  my $s = shift;
  if ($s) {
    fits_report_error(*STDERR, $status);
    exit(1);
  }
}

sub _help {
  exec('perldoc', '-F', $FindBin::Bin . '/' . $FindBin::RealScript);
}

sub _version {
  print $version,"\n";
  exit 0;
}
