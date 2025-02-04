#! /usr/bin/perl -w
use strict;

my $version = '0.1';

use Config;
use lib '/home/rpete/local/perlmods';
use lib '/home/rpete/local/perlmods/'.$Config{archname};

use Chandra::Tools::Common;
BEGIN {
  $^W = 0;
  require PDL;
  import PDL;
}
$^W=1;
use PDL::Graphics::PGPLOT;
use Chandra::Constants qw( RAD_PER_DEG );
use Astro::FITS::CFITSIO;
use IO::Handle;
use PGPLOT;
use Math::Trig qw( asin );

STDERR->autoflush(1);

use Getopt::Long;
my %default_opts = (
		    extname => 'events',
		    outbase => 'dither_split',
		    segments => 4,
		    unroll => 1,
		    resroll => 1,
		    );
my %opts = %default_opts;
GetOptions(\%opts,
	   'help!', 'version!', 'outbase=s', 'view!', 'segments=i', 'unroll!',
	   'resroll!',
	   ) or die "Try `$0 --help' for more information.\n";
$opts{help} and _help();
$opts{version} and _version();

@ARGV >= 2 or die "Invalid arguments\nTry `$0 --help' for more information.\n";
my $args = "@ARGV"; # used to write new HISTORY

# nasty stuff atm
if ($opts{segments} != 2 and $opts{segments} != 4 and $opts{segments} !=8) {
  die "segments must be 2, 4 or 8\n";
}

my $status = 0;

my $DATE;
Astro::FITS::CFITSIO::fits_get_system_time($DATE,undef,$status);
my $CREATOR = $0; $CREATOR =~ s/(.*\/)//;

my $evtfile = pop @ARGV;
my @aspsol = @ARGV;

# get the nominal telescope pointing (assumes constant across aspect files)
print STDERR "Reading aspect files...";
my ($time, $ra, $dec) = _read_aspsols(@aspsol);
print STDERR "done\n";

my (undef, undef, $timediff_median) = ($time->slice('1:-1') - $time->slice('0:-2'))->stats;
my $timediff_threshold = 10 * $timediff_median;

=begin comment

my ($ra_mid, $dec_mid) = _bisect($ra,$dec);
my ($gti_start, $gti_stop) = _make_gti(
				       $time->index(which($ra<$ra_mid & $dec>$dec_mid)),
				       $timediff_threshold
				       );
_write_files( $evtfile, [$gti_start], [$gti_stop] );

=cut

my ($gti_start, $gti_stop) = _bisect2($time, $ra, $dec, _log2($opts{segments}), [], [], $timediff_threshold);
#my ($gti_start, $gti_stop) = _bisect2($time, $ra, $dec, 2, [], [], $timediff_threshold);

# this is for interactively verifying that the gti returned are suitable
if ($opts{view}) {
  for (0..$#{$gti_start}) {
    $gti_start->[$_]->nelem or next;
    line $ra, $dec;
    hold;
    my $mask = Chandra::Tools::Common::good_time_mask($time,$gti_start->[$_],$gti_stop->[$_]);
    line $ra->index(which($mask)), $dec->index(which($mask)), {COLOR => 'red' };
    release;
    print "press enter to continue...";
    <STDIN>;
  }
}

_write_files($evtfile, $gti_start, $gti_stop);

exit 0;

sub _bisect2 {
  my ($time, $ra, $dec, $n, $start, $stop, $threshold) = @_;

  my ($ra_mid, $dec_mid) = _bisect($ra,$dec);

  my @i = (
	   which($ra<$ra_mid),
	   which($ra>$ra_mid),
	  );

  if ($n < 2) {
    for (@i) {
#      $_->nelem > 1 or next;
      my ($s1, $s2) = _make_gti($time->index($_), $threshold);
      push @$start, $s1;
      push @$stop, $s2;
    }
  }
  else {
    for (@i) {
      _bisect2($time->index($_), $ra->index($_), $dec->index($_), $n-1, $start, $stop, $threshold);
    }
  }

  return ($start, $stop);
}

# reads list of aspect solutions files, returns times and rotated positions (sorted by time)
sub _read_aspsols {
  my @files = @_;

  my ($ra, $dec, $time);
  $_ = null for $ra, $dec, $time;

  for (@files) {
    my $fptr = Astro::FITS::CFITSIO::open_file($_, Astro::FITS::CFITSIO::READONLY(), $status);
    check_status($status) or die;
    $fptr->movnam_hdu(Astro::FITS::CFITSIO::BINARY_TBL(), 'aspsol', 0, $status);
    check_status($status) or die;
    my $h = $fptr->read_header;
    exists $h->{$_} or die for qw( RA_NOM DEC_NOM ROLL_NOM );
    my ($timetmp, $ratmp, $dectmp) = read_bintbl_cols($fptr, 'time', 'ra', 'dec') or die $_;
    $fptr->close_file($status);


    if ($opts{unroll}) {
      ($ratmp, $dectmp) = _rotate($ratmp, $dectmp,
				  $h->{RA_NOM},
				  $h->{DEC_NOM},
				  $h->{ROLL_NOM} * RAD_PER_DEG,
				 );

      if ($opts{resroll}) {
	# look for "residual roll", examples of this are obsids 1248, 1420

	my $min_ra_ind = minimum_ind($ratmp);
	my $max_ra_ind = maximum_ind($ratmp);
	my ($min_ra, $dec_at_min_ra) = (
					$ratmp->at($min_ra_ind),
					$dectmp->at($min_ra_ind)
				       );
	my ($max_ra, $dec_at_max_ra) = (
					$ratmp->at($max_ra_ind),
					$dectmp->at($max_ra_ind)
				       );

	# first angle
	my ($ideal_corner_ra, $ideal_corner_dec) = (
						    $min_ra,
						    $dec_at_max_ra,
						   );
	my $min_dist_ind =
	  minimum_ind(
		      sqrt(
			   ($ratmp-$ideal_corner_ra)**2 +
			   ($dectmp-$ideal_corner_dec)**2
			  )
		     );
	my $angle1 = asin( ($ratmp->at($min_dist_ind) - $min_ra) /
			   sqrt(($min_ra-$ratmp->at($min_dist_ind))**2 +
				($dec_at_min_ra-$dectmp->at($min_dist_ind))**2
			       )
			 );
	$angle1 *= -1 if $dec_at_min_ra > $dectmp->at($min_dist_ind);

	# second angle
	($ideal_corner_ra, $ideal_corner_dec) = (
						 $max_ra,
						 $dec_at_min_ra,
						);
	$min_dist_ind =
	  minimum_ind(
		      sqrt(
			   ($ratmp-$ideal_corner_ra)**2 +
			   ($dectmp-$ideal_corner_dec)**2
			  )
		     );
	my $angle2 = asin( ($max_ra - $ratmp->at($min_dist_ind)) /
			   sqrt(($max_ra-$ratmp->at($min_dist_ind))**2 +
				($dec_at_max_ra-$dectmp->at($min_dist_ind))**2
			       )
			 );

	$angle2 *= -1 if $dec_at_max_ra < $dectmp->at($min_dist_ind);

	my $ratio = 1.3;

	my $max_diff = 2; # degrees
	if (abs($angle1-$angle2) > $max_diff * RAD_PER_DEG) {
#	if ($angle1/$angle2 > $ratio or $angle1/$angle2<1/$ratio) {
	  print STDERR "attempt at \"residual roll\" correction failed: angle1 = $angle1, angle2=$angle2\n";
	}
	else {
	  print STDERR "angle1 = $angle1, angle2 = $angle2\n";
	  ($ratmp, $dectmp) = _rotate($ratmp, $dectmp,
				      $h->{RA_NOM},
				      $h->{DEC_NOM},
				      -($angle1+$angle2)/2
				 );
	  }
      }

    }

=begin comment

    # append was deemed too wasteful of memory
    # ...but this doesn't work...oh well...
    $time->reshape($time->nelem+$timetmp->nelem);
    (my $tmp=$time->mslice([$time->nelem-$timetmp->nelem,-1])) .= $timetmp;

    $ra->reshape($ra->nelem+$ratmp->nelem);
    ($tmp=$ra->mslice([$ra->nelem-$ratmp->nelem,-1])) .= $ratmp;

    $dec->reshape($dec->nelem+$dectmp->nelem);
    ($tmp=$dec->mslice([$dec->nelem-$dectmp->nelem,-1])) .= $dectmp;

=cut

#=begin comment

    $time = append($time, $timetmp);
    $ra = append($ra, $ratmp);
    $dec = append($dec, $dectmp);

#=cut

  }

  my $sindex = qsorti($time);
  $_ = $_->index($sindex) for $time, $ra, $dec;
  return ($time, $ra, $dec);
}

sub _write_files {
  my ($file, $start, $stop) = @_;

  my $status = 0;
  my $fptr = Astro::FITS::CFITSIO::open_file($file, Astro::FITS::CFITSIO::READONLY(), $status);
  check_status($status) or die "could not open FITS file $file";

  my ($n_hdus, $event_hdu_num) = _get_hdu_nums($fptr,$opts{extname});

  # array of output file names
  my @outfiles = map { '!' . $opts{outbase} . sprintf("_%.2d.fits", $_) } 1..@$start;

  # use only those gti that have elements
  my @i = grep $start->[$_]->nelem, 0..$#{$start};
  if (@i != @outfiles) {
    $start = [ @{$start}[@i] ];
    $stop = [ @{$stop}[@i] ];
    @outfiles = @outfiles[@i];
  }

  # create output fitsfilePtr objects
  my @outfptrs = map {
    Astro::FITS::CFITSIO::create_file($_, $status);
  } @outfiles;
  check_status($status) or die "failed to create '$_'";


  print STDERR "Copying leading HDUs...";
  for my $i (1..$event_hdu_num-1) {
    for (@outfptrs) {
      _copy_hdu($fptr, $_, $i, 0) or
	die "error copying HDU number $i";
    }
  }
  print STDERR "done\n";

  $fptr->movabs_hdu($event_hdu_num, undef, $status);
  _really_write($fptr, \@outfptrs, $start, $stop);

  print STDERR "Copying trailing HDUs...";
  for my $i ($event_hdu_num+1..$n_hdus) {
    for (@outfptrs) {
      _copy_hdu($fptr, $_, $i, 0) or
	die "error copying HDU number $i";
    }
  }
  print STDERR "done\n";

  $fptr->close_file($status);
  $_->close_file($status) for @outfptrs;

}

sub _really_write {
  my ($in, $out, $start, $stop) = @_;

  print STDERR "Reading event times...";
  my ($time) = Chandra::Tools::Common::read_bintbl_cols($in, 'time', {status=>1}) or die;
  print STDERR " done\n";

  print STDERR "Calculating masks...", ' 'x5;
  my @masks = map {
    print STDERR "\b"x5;
    printf STDERR "%.2d/%.2d", $_+1, scalar @$start;
    Chandra::Tools::Common::good_time_mask($time, $start->[$_], $stop->[$_])
    } 0..$#{$start};
  print STDERR " done\n";

  my @nrows = (0)x@masks;

  my $status = 0;

  my $hdr = $in->read_header();

=begin comment

  my (@ttype, @tform, @tunit, @tlmin, @tlmax,
      @tcnam, @tctyp, @tcrvl, @tcrpx, @tcdlt,
      %cols);
  exists $hdr->{TFIELDS} or return;
  my $j = 0;
  for (my $i=1; $i<=$hdr->{TFIELDS}; $i++) {

    my ($ttype,$tform) = ($hdr->{'TTYPE'.$i}, $hdr->{'TFORM'.$i});
    my $tunit = exists $hdr->{'TUNIT'.$i} ? $hdr->{'TUNIT'.$i} : '' ;
    my $tlmin = exists $hdr->{'TLMIN'.$i} ? $hdr->{'TLMIN'.$i} : undef ;
    my $tlmax = exists $hdr->{'TLMAX'.$i} ? $hdr->{'TLMAX'.$i} : undef ;

    my $tcnam = exists $hdr->{'TCNAM'.$i} ? $hdr->{'TCNAM'.$i} : undef ;
    my $tctyp = exists $hdr->{'TCTYP'.$i} ? $hdr->{'TCTYP'.$i} : undef ;
    my $tcrvl = exists $hdr->{'TCRVL'.$i} ? $hdr->{'TCRVL'.$i} : undef ;
    my $tcrpx = exists $hdr->{'TCRPX'.$i} ? $hdr->{'TCRPX'.$i} : undef ;
    my $tcdlt = exists $hdr->{'TCDLT'.$i} ? $hdr->{'TCDLT'.$i} : undef ;
    defined($_) and s/^'(.*?)\s*?'/$1/ for ($ttype,$tform,$tunit,$tlmin,$tlmax);

    push @ttype, lc $ttype;
    push @tform, $tform;
    push @tunit, $tunit;
    push @tlmin, $tlmin;
    push @tlmax, $tlmax;

    push @tcnam, $tcnam;
    push @tctyp, $tctyp;
    push @tcrvl, $tcrvl;
    push @tcrpx, $tcrpx;
    push @tcdlt, $tcdlt;

    $j++;
    $cols{$ttype} = { tform => $tform, incolnum => $i, outcolnum => $j };
  }

  for (@$out) {
    $_->insert_btbl(0,scalar(@ttype),\@ttype,\@tform,\@tunit,$opts{extname},0,$status);
    check_status($status) or return;
  }

  # start by inserting all keys that we can
  my $nkeys;
  $in->get_hdrspace($nkeys, undef, $status);
  my %key_types;
  @key_types{ Astro::FITS::CFITSIO::TYP_NULL_KEY(),
              Astro::FITS::CFITSIO::TYP_HDUID_KEY(),
              Astro::FITS::CFITSIO::TYP_CKSUM_KEY(),
              Astro::FITS::CFITSIO::TYP_WCS_KEY(),
              Astro::FITS::CFITSIO::TYP_REFSYS_KEY(),
              Astro::FITS::CFITSIO::TYP_COMM_KEY(),
              Astro::FITS::CFITSIO::TYP_CONT_KEY(),
              Astro::FITS::CFITSIO::TYP_USER_KEY(),
              Astro::FITS::CFITSIO::TYP_RANG_KEY(),
             } = ();
  for (1..$nkeys) {
    my $card;
    $in->read_record($_, $card, $status);
    my $type = Astro::FITS::CFITSIO::fits_get_keyclass($card);
    for (@$out) {
      $_->write_record($card, $status) if exists $key_types{$type};
    }
  }

=cut

  my (@ttype, %cols);
  exists $hdr->{TFIELDS} or return;
  my $j = 0;
  for (my $i=1; $i<=$hdr->{TFIELDS}; $i++) {

    my ($ttype,$tform) = (lc($hdr->{'TTYPE'.$i}), $hdr->{'TFORM'.$i});
    defined($_) and s/^'(.*?)\s*?'/$1/ for $ttype, $tform;

    push @ttype, $ttype;

    $j++;
    $cols{$ttype} = { tform => $tform, incolnum => $i, outcolnum => $j };
  }

  for (@$out) {
    $in->copy_header($_,$status);
    $_->modify_key_lng('NAXIS2', 0, 'number of rows in table', $status);
    check_status($status) or return;
  }
  $_->write_history("$0 $args",$status) for @$out;

  my $nrows;
  $in->get_num_rows($nrows,$status);
  $opts{nrows} or $in->get_rowsize($opts{nrows}=0, $status);

  $opts{nrows} = $nrows if ($opts{nrows} < 1 or $opts{nrows} > $nrows);

  #
  # set up piddles
  #
  my %datatypes = (
		   'A' => { 'pdl' => undef, 'cfitsio' => Astro::FITS::CFITSIO::TSTRING(), },
		   'I' => { 'pdl' => short, },
		   'J' => { 'pdl' => long, },
		   'E' => { 'pdl' => float, },
		   'D' => { 'pdl' => double, },
		   'X' => { 'pdl' => byte, 'cfitsio' => Astro::FITS::CFITSIO::TBIT(), },
		  );

  for my $dt (keys %datatypes) {
    next if exists $datatypes{$dt}{'cfitsio'};
    $datatypes{$dt}{'cfitsio'} = match_datatype($datatypes{$dt}{'pdl'});
    if ($datatypes{$dt}{'cfitsio'} == -1) {
      carp("no matching CFITSIO datatype found for TFORM '$dt'");
      return;
    }
  }

  for my $ttype (@ttype) {
    # repeat==0 not handled
    my ($repeat, $type) = $cols{$ttype}{tform} =~ /^(\d*)([A-Z])$/ or
      carp("unrecognized TFORM = '$cols{$ttype}{tform}'"),
	return;
    $cols{$ttype}{repeat} = $repeat ? $repeat : 1;
    exists $datatypes{$type} or
      carp("unrecognized TFORM = '$cols{$ttype}{tform}'"),
	return;
    if ($type eq 'A') {
      $cols{$ttype}{'pdl'} = [];
    } else {
      $cols{$ttype}{'pdl'} = $repeat > 1 ?
	zeroes($datatypes{$type}{'pdl'}, $repeat, $opts{nrows}) :
	  zeroes($datatypes{$type}{'pdl'}, $opts{nrows})

	}
    $cols{$ttype}{cfitsio_datatype} = $datatypes{$type}{'cfitsio'};
  }

  print STDERR "Writing event lists...    ";

  my $old_packing = Astro::FITS::CFITSIO::PerlyUnpacking(-1);
  Astro::FITS::CFITSIO::PerlyUnpacking(0);
  my $rows_done = 0;

    while (1) {

    print STDERR (("\b"x4).sprintf(" %2d",int(100*$rows_done/$nrows)).'%');
    my $i;

    my $rows_this_time = $opts{nrows};
    $rows_this_time = $nrows-$rows_done if ($rows_this_time > $nrows-$rows_done);

    for my $ttype (@ttype) {

      # don't re-read time column, since we already have it
      if ($ttype eq 'time') {
	(my $tmp = $cols{$ttype}{'pdl'}->mslice([0,$rows_this_time-1]))
	  .= $time->mslice([$rows_done, $rows_done+$rows_this_time-1]);
      }
      elsif ($cols{$ttype}{cfitsio_datatype} == Astro::FITS::CFITSIO::TSTRING()) {
	$in->read_col($cols{$ttype}{cfitsio_datatype},
		      $cols{$ttype}{incolnum},
		      $rows_done+1, 1,
		      $rows_this_time, '',
		      $cols{$ttype}{'pdl'}, undef,
		      $status);
      } else {
	$in->read_col($cols{$ttype}{cfitsio_datatype},
		      $cols{$ttype}{incolnum},
		      $rows_done+1, 1,
		      $cols{$ttype}{repeat}*$rows_this_time, 0,
		      ${$cols{$ttype}{'pdl'}->get_dataref},
		      undef,$status);
	$cols{$ttype}{'pdl'}->upd_data;
      }
      check_status($status) or
	carp("error reading from input event list"),
	  return;

      #
      # write rows
      #
      for my $i (0..$#masks) {

	my $time_mask = $masks[$i]->mslice([$rows_done, $rows_done+$rows_this_time-1]);
	my $maski = which($time_mask);
	next unless $maski->nelem;
	my $rows_added = $maski->nelem;

=begin comment

	# gotta be a better way
	if ($cols{$ttype}{'pdl'}->dims > 1) {
	  my $mask_2d = zeroes(long, ($cols{$ttype}{'pdl'}->dims)[0], $rows_this_time);
	  my $tmp;
	  ($tmp = $mask_2d->slice("($_),")) .= $time_mask for 0..($cols{$ttype}{'pdl'}->dims)[0]-1;
	  $maski = which($mask_2d->clump(-1));
	}

=cut

        if ($cols{$ttype}{repeat} > 1) {
	  my $r = $cols{$ttype}{repeat};
	  $maski = ($maski->dummy(0,$r)*$r+sequence($r))->clump(-1);
	}

	if ($cols{$ttype}{cfitsio_datatype} == Astro::FITS::CFITSIO::TSTRING()) {
	  $out->[$i]->write_col($cols{$ttype}{cfitsio_datatype},
				$cols{$ttype}{outcolnum},
				$nrows[$i]+1, 1,
				$maski->nelem,
				[ @{ $cols{$ttype}{'pdl'} }{$maski->list} ],
				$status);
	} else {
	  $out->[$i]->write_col($cols{$ttype}{cfitsio_datatype},
				$cols{$ttype}{outcolnum},
				$nrows[$i]+1, 1,
				$maski->nelem,
				$cols{$ttype}{'pdl'}->clump(-1)->index($maski)->get_dataref,
				$status);
	}

	# update output row counts if this is the last column we're doing
	$nrows[$i] += $rows_added if $ttype eq $ttype[-1];

	check_status($status) or
	  carp("error writing to output event list"),
	    return;
      }

    }
    $rows_done += $rows_this_time;
    last if $rows_done >= $nrows;
  }

  print STDERR (("\b"x4).'100%');

  print STDERR " done\n";

  for (@$out) {
    $_->update_key(Astro::FITS::CFITSIO::TSTRING(),'CREATOR',$CREATOR,undef,$status);
    $_->update_key(Astro::FITS::CFITSIO::TSTRING(),'DATE',$DATE,undef,$status);
    $_->write_chksum($status);
  }

  check_status($status) or die;
  Astro::FITS::CFITSIO::PerlyUnpacking($old_packing);

  return 1;
}

# Copies HDU number $hdunum from $infptr to $outfptr.
# $return_to_old_hdu is a boolean flag indicating whether
# $infptr should be repositioned to it's pre-called HDU
# number prior to returning.
sub _copy_hdu($$$$) {
  my ($infptr,$outfptr,$hdunum,$return_to_old_hdu) = @_;

  my $status = 0;

  my $old_hdu_num = $infptr->get_hdu_num(undef);
  $infptr->movabs_hdu($hdunum,undef,$status);
  $infptr->copy_hdu($outfptr,0,$status);
  $outfptr->update_key(Astro::FITS::CFITSIO::TSTRING(),'CREATOR',$CREATOR,undef,$status);
  $outfptr->update_key(Astro::FITS::CFITSIO::TSTRING(),'DATE',$DATE,undef,$status);
  $outfptr->update_chksum($status);
  $infptr->movabs_hdu($old_hdu_num) if $return_to_old_hdu;
  check_status($status) or return;

  return 1;
}

# Returns number of HDUs in file, as well as HDU number of the
# given extension=$target_hdunam.
sub _get_hdu_nums($$) {
  my ($fptr,$target_hdunam) = @_;

  my $status = 0;
  my $current_hdunum = $fptr->get_hdu_num(undef);

  my $numhdus;
  $fptr->get_num_hdus($numhdus,$status);

  $fptr->movnam_hdu(Astro::FITS::CFITSIO::ANY_HDU(),$target_hdunam,0,$status);
  my $target_hdunum = $fptr->get_hdu_num(undef);

  $fptr->movabs_hdu($current_hdunum,undef,$status);

  check_status($status) or return;

  return($numhdus,$target_hdunum);
}

# finds gaps and returns start/stop intervals
sub _make_gti {
  my ($time, $threshold) = @_;

  $time->nelem > 1 or return (pdl([]), pdl([]));
  my $index = which(
		    $time->slice('1:-1')-$time->slice('0:-2') >
		    $threshold
		   );

  my $gti_start = zeroes($index->nelem+1);
  my $gti_stop = $gti_start->copy;

  my $tmp;

  $gti_start->set(0, $time->at(0));
  $gti_stop->set(-1, $time->at(-1));

  if ($gti_stop->nelem>1) {
    ($tmp = $gti_stop->mslice([0,-2])) .= $time->index($index);
    ($tmp = $gti_start->mslice([1,-1])) .= $time->index($index+1);
  }

  return ($gti_start, $gti_stop);
}

# finds bisection point of event list, currently very simple
sub _bisect {
  my ($x, $y) = @_;

  my ($x_min, $x_max) = $x->minmax;
  my ($y_min, $y_max) = $y->minmax;

  return
    ($x_max + $x_min) / 2,
    ($y_max + $y_min) / 2;
}

# rotates events by a given angle (radians)
sub _rotate {
  my ($x, $y, $xoff, $yoff, $angle) = @_;

  $x = $x - $xoff;
  $y = $y - $yoff;
  my $xcopy = $x->copy;
  $x = $x * cos($angle) + $y * sin($angle);
  $y = $y * cos($angle) - $xcopy * sin($angle);

  return $x+$xoff, $y+$yoff;
}

sub _help {
  print <<EOP;
Usage: $0 [options] pcad_asol1_1 pcad_asol1_2 ... evtfile

  --help          show help and exit
  --version       show version and exit
  --outbase       default is '$default_opts{outbase}'
  --view          interactively display aspect positions in each slice
  --segments=N    number of slices for aspect solution, default is 4.
                  valid values at this time are only 2, 4 and 8. To be
                  fixed...
  --nounroll, --noresroll

EOP
  exit 0;
}

sub _version {
  print $version,"\n";
  exit 0;
}

sub _log2 {
  return int(log($_[0]) / log(2));
}
