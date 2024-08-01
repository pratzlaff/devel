#! /usr/bin/perl -w
use strict;

$| = 1;

use Config;
use lib '/home/rpete/local/perlmods';
use lib '/home/rpete/local/perlmods/'.$Config{archname};

use PDL;
use PDL::Fit::Polynomial;
use Chandra::Tools::Common;
use Getopt::Long;

my %default_opts = ();
my %opts = %default_opts;
GetOptions(\%opts,
	   'help!'
	   ) or die "Try \`$0 --help\' for more information.\n";
$opts{help} and help();

@ARGV == 1 or
    die "invalid arguments\nTry \`$0 --help\' for more information.\n";

my $file = shift;
print STDERR "Reading events...";
my ($tg_r, $tg_lam) = read_bintbl_cols($file,'tg_r', 'tg_lam',
				       {extname=>'events', status=>1}
				       ) or die;
print STDERR " done\n";

my $i = which $tg_lam > 5 & $tg_r > 0;# & $tg_r < inf;
$i->nelem or die;

my ($yfit, $coeffs) = fitpoly1d $tg_r->index($i), $tg_lam->index($i), 2;
print 'TG_LAM = TG_R * '. $coeffs->at(1) .' + '. $coeffs->at(0) . "\n";
print 'Max deviation in fitted TG_LAM = '. ($yfit-$tg_lam->index($i))->abs->max . "\n";

exit 0;

sub help {
    print <<EOP;
Usage: $0 [option] evtfile

  --help       show help and exit
EOP

    exit 0;
}
