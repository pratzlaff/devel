#! /usr/bin/perl -w

use strict;

use Chandra::Tools::Common;
use Getopt::Long;
use PDL;
use Carp;

my %opts = (
	    );
GetOptions(\%opts,
	   'help!',
	   ) or usage();
$opts{help} and usage();

@ARGV == 2 or usage();

my ($evtfile, $gtifile) = @ARGV;

print STDERR "Reading events file...";
my ($time) = read_bintbl_cols($evtfile,'time',{status=>1,extname=>'events'});
print STDERR " done\n";
defined $time or
    confess "could not read event file '$evtfile'";

print STDERR "Reading GTI file...";
my ($start,$stop) = read_bintbl_cols($gtifile,'start','stop',{status=>1,extname=>'gti'});
print STDERR " done\n";
defined $time or
    confess "could not read GTI file '$gtifile'";

my $length = $stop-$start;
my $counts = zeroes(long,$start->nelem);

for (my $i=0; $i<$stop->nelem; $i++) {
    $counts->set($i,
		 which($time>=$start->at($i) & $time<=$stop->at($i))->nelem,
		 );
}
my $rate = ($counts/$length)->badmask(-1);

#
# print output
#

print <<EOP;
start	stop	length	counts	rate
N	N	N	N	N
EOP

wcols "%d\t%d\t%d\t%d\t%.1f", $start, $stop, $length, $counts, $rate, *STDOUT;

exit 0;

sub usage {
    print STDERR <<EOP;
Usage: $0 [options] evtfile gtifile

  Options:
  --help     This message.

EOP
    exit 1;
}
