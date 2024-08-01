#!/usr/bin/perl

#
# deadtime_filter obsid_list.txt obsid_path
#
# INPUT:
# obsid_list.txt -> text file list of ObsIDs, one per line including 
# path.
# ex. /data/lentil/HZ43/1012
#
# Jennifer Posson-Brown
# Nick Durham, updated/edited 3/2/2011
#


$dirfile=$ARGV[0];

open(PATHDIR, $dirfile);
while (<PATHDIR>){
    @tmp=split;
    $dir=trim($tmp[0]);

    # Find dtf1.fits in primary dir
    $blah = `ls $dir/primary/hrc*dtf1.fits*`;
    $dtf = trim($blah);

    # Filter dtf1>0.98 output file: primary/gti_dtf098.fits
    print `punlearn dmgti`;
    print `dmgti $dtf ${dir}/primary/gti_dtf098.fits userlimit="dtf>0.98" clobber=yes mode=h verbose=2`;

    # Find repro'ed evt2 file
    $blah = `ls $dir/tg_repro/*evt2.fits`;
    $evt = trim($blah);

    # Apply GTIs from dtf>0.98 file to evt2 file, output:tg_repro/evt2_098.fits
    print `punlearn dmcopy`;
    print `dmcopy "${evt}[EVENTS][\@${dir}/primary/gti_dtf098.fits]" ${dir}/tg_repro/evt2_098.fits clobber=yes mode=h verbose=2`;
 
    # Append the REGION block from the old repro'ed evt2 to the dmcopy'ed evt2
    print `dmappend "${evt}[REGION][subspace -time]" ${dir}/tg_repro/evt2_098.fits`;

    $gti="${dir}/tg_repro/evt2_098.fits[EVENTS]";
    $outfile="${dir}/primary/dtfstat_098.fits";

    print `punlearn hrc_dtfstats`;
    print `pset hrc_dtfstats infile=${dtf}`;
    print `pset hrc_dtfstats outfile=${outfile}`;
    print `pset hrc_dtfstats gtifile=${gti}`;
    print `pset hrc_dtfstats verbose=3`;
    print `pset hrc_dtfstats clobber=yes`;
    print `pset hrc_dtfstats mode=h`;
    print `hrc_dtfstats`;



    # Update DTCOR, ONTIME, EXPOSURE header values
    $olddtcor = `dmkeypar $evt DTCOR echo+`;
    $olddtor = trim($olddtcor);

    $foo=`dmlist \"${outfile}[cols DTCOR]\" data,clean`;
    my ($dtcor) = ($foo =~ /\#\s+DTCOR\s+([0-9\.\-]+)/s);
    print "$olddtcor\t$dtcor\t \n";

    $evt1="${dir}/tg_repro/evt2_098.fits";

    print `punlearn dmkeypar`;
    $tmp= `dmkeypar $evt1 ONTIME echo+`;
    $ontime=trim($tmp);
    $livetime=$ontime * $dtcor;
    $exposure=$ontime * $dtcor;

    print `punlearn dmhedit`;
    print `dmhedit ${evt1} filelist=\"\" op=add key=LIVETIME value=${livetime}`;
    print `dmhedit ${evt1} filelist=\"\" op=add key=EXPOSURE value=${exposure}`;
    print `dmhedit ${evt1} filelist=\"\" op=add key=DTCOR value=${dtcor}`;


}

close(OBS);


sub trim {
    my @out = @_;
    for (@out){
        s/^\s+//;
        s/\s+$//;
    }
    return wantarray ? @out: $out[0];
}
