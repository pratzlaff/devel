$| = 1;

#
# Input tg_r, tg_d need only be rotated properly. Offsets from zero are fine.
#

use Chandra::Tools::Common;
use Chandra::Tools::Image;
use PGPLOT;
use PDL;
use PDL::Fit::Polynomial;
use Carp;

my $um_per_deg = 150600;

sub findit {

    my @plate_limits_tg_r = (-0.3, 0.3);

    my %opts  = parse_opts(\@_, 'max', 'min', 'dev');
    defined $opts{min} or $opts{min} = 0;
    defined $opts{max} or  $opts{max} = 10;

    my (@x, @y, $x, $y, $key);

    my ($tg_r, $tg_d) = (shift, shift);

    my $i = new Chandra::Tools::Image $tg_r, -$tg_d, {xrange=>[-1,1],
						      yrange=>[-2e-3,2e-3]};
    $i->xtitle('tg_r');
    $i->ytitle('-tg_d');

    $i->plot({min=>$opts{min}, max=>$opts{max}, grey=>1,});
    pgsci(2);

    @x = @y = ();
    print "Choose central segment upper bounding region...";
    while (1) {
	pgcurs($x,$y,$key);
	last if $key ne 'A';
	push @x, $x;
	push @y, $y;
    }
    @x >= 2 or
	carp("require 2 or more points"),
	return;
    print "\n";
    my ($upper_mean) = stats(pdl(@y));

    @x = @y = ();
    print "Choose central segment lower bounding region...";
    while (1) {
	pgcurs($x,$y,$key);
	last if $key ne 'A';
	push @x, $x;
	push @y, $y;
    }
    @x >= 2 or
	carp("require 2 or more points"),
	return;
    print "\n";
    my ($lower_mean) = stats(pdl(@y));

    my $width = $upper_mean - $lower_mean;
    pgline(2,\@plate_limits_tg_r,[-$width/2,-$width/2]);
    pgline(2,\@plate_limits_tg_r,[$width/2,$width/2]);

    printf "\nCentral plate width = %d\n", $width*$um_per_deg;

    @x = @y = ();
    print "Choose bounding line slope...";
    while (1) {
	pgcurs($x,$y,$key);
	last if $key ne 'A';
	push @x, $x;
	push @y, $y;
    }
    @x >= 2 or
	carp("require 2 or more points"),
	return;
    print "\n";
    my ($yfit,$coeffs) = fitpoly1d(pdl(@x),pdl(@y),2);
    print $coeffs,"\n";
    my $slope = $coeffs->at(1);
    my @plot_x;
    @plot_x = ($plate_limits_tg_r[1], 2);

    pgline(2, \@plot_x,
	   [abs($slope) * ($plot_x[0]-$plot_x[0])+$width/2,
	    abs($slope) * ($plot_x[1]-$plot_x[0])+$width/2]
	   );
    pgline(2, \@plot_x,
	   [-abs($slope) * ($plot_x[0]-$plot_x[0])-$width/2,
	    -abs($slope) * ($plot_x[1]-$plot_x[0])-$width/2]
	   );

    @plot_x = ($plate_limits_tg_r[0], -2);
    pgline(2, \@plot_x,
	   [-abs($slope) * ($plot_x[0]-$plot_x[0])+$width/2,
	    -abs($slope) * ($plot_x[1]-$plot_x[0])+$width/2]
	   );
    pgline(2, \@plot_x,
	   [abs($slope) * ($plot_x[0]-$plot_x[0])-$width/2,
	    abs($slope) * ($plot_x[1]-$plot_x[0])-$width/2]
	   );

    _write_text($width,$slope);

    pgsci(1);

    #
    # replot (usually for hard-copy
    #
    if (defined $opts{dev}) {
	$i->plot({min=>$opts{min}, max=>$opts{max}, grey=>1, dev=>$opts{dev}});
	pgsci(2);
	pgline(2,\@plate_limits_tg_r,[-$width/2,-$width/2]);
	pgline(2,\@plate_limits_tg_r,[$width/2,$width/2]);
	my @plot_x = ($plate_limits_tg_r[1], 2);
	pgline(2, \@plot_x,
	       [abs($slope) * ($plot_x[0]-$plot_x[0])+$width/2,
		abs($slope) * ($plot_x[1]-$plot_x[0])+$width/2]
	       );
	pgline(2, \@plot_x,
	       [-abs($slope) * ($plot_x[0]-$plot_x[0])-$width/2,
		-abs($slope) * ($plot_x[1]-$plot_x[0])-$width/2]
	       );

	@plot_x = ($plate_limits_tg_r[0], -2);
	pgline(2, \@plot_x,
	       [-abs($slope) * ($plot_x[0]-$plot_x[0])+$width/2,
		-abs($slope) * ($plot_x[1]-$plot_x[0])+$width/2]
	       );
	pgline(2, \@plot_x,
	       [abs($slope) * ($plot_x[0]-$plot_x[0])-$width/2,
		abs($slope) * ($plot_x[1]-$plot_x[0])-$width/2]
	       );

	_write_text($width,$slope);

	pgsci(1);
	pgclos();
    }
    
}

sub _write_text {
    my ($width, $slope) = @_;

    my ($x1,$x2,$y1,$y2);
    pgqwin($x1,$x2,$y1,$y2);
    pgtext($x1 + ($x2-$x1) * 0.1, $y2 - ($y2-$y1) * 0.05,
	   sprintf("central width = %d \\gm", int($width*$um_per_deg))
	   );
    pgtext($x1 + ($x2-$x1) * 0.1, $y2 - ($y2-$y1) * 0.10,
	   sprintf("slope = %.3e", abs($slope))
	   );
}
