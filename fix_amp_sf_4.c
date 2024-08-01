/*
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
                 fix_amp_sf
                 M. Juda
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

Correct the values reported in telemetry for AMP_SF

$Header: /juda1.real/juda1/juda/asc/hrc/code/evt_tools/RCS/fix_amp_sf_3.c,v 1.2 2001/11/21 20:07:46 juda Exp $

*/

/*** include files ***/
#include <stdio.h>
#include <string.h>
#include <unistd.h>
#include <stdlib.h>
#include <math.h>

#include "fitsio.h"

#define CALLOC(n,x)  ((x *) calloc(n,sizeof(x)))

#define GAIN 74.0
#define THRESH1 8
#define THRESH2 16
#define THRESH3 32
#define PHA_1TO2 50.5
#define PHA_2TO3 99.5
#define WIDTH1 2.0
#define WIDTH2 2.0

void printerror(int status)
{
    /*****************************************************/
    /* Print out cfitsio error messages and exit program */
    /*****************************************************/

    char status_str[FLEN_STATUS], errmsg[FLEN_ERRMSG];
  
    if (status)
      fprintf(stderr, "\n*** Error occurred during program execution ***\n");

    fits_get_errstatus(status, status_str);   /* get the error description */
    fprintf(stderr, "\nstatus = %d: %s\n", status, status_str);

    /* get first message; null if stack is empty */
    if ( fits_read_errmsg(errmsg) ) 
    {
         fprintf(stderr, "\nError message stack:\n");
         fprintf(stderr, " %s\n", errmsg);

         while ( fits_read_errmsg(errmsg) )  /* get remaining messages */
             fprintf(stderr, " %s\n", errmsg);
    }

    exit( status );       /* terminate the program, returning error status */
}

/*============================================================*/
int main(argc,argv)
int argc;
char *argv[];
{
  char *progname, c, *inname, *outname;
  int kk, i, j;

  /* FITSIO variables */
  fitsfile *infile, *outfile;
  int bitpix = 16, hdutype, status = 0, anynull, hdunum;
  short snull = 0;
  long naxis = 0;
  long naxes[2] = {0, 0};
  long firstrow, firstelem;
  int sf_colnum, au1_colnum, au2_colnum, au3_colnum, av1_colnum, av2_colnum, 
    av3_colnum, pha_colnum;
  int tfields;
  long nrows = 0, numrows, i_numrows, pcount;
  int maxdim = 99;
  char extname[FLEN_VALUE];
  char **ttype;
  char **tform;
  char **tunit;
  char comment[FLEN_COMMENT];

  /* these are the output columns of the EVENTS extension of the FITS file */
  double *time;
  long *mjf, *startmnf, *stopmnf, *clkticks;
  unsigned char  *crsv, *crsu, *amp_sf, *pha, *e_trig, *vetostt, *det_id, 
    *sub_mjf, *quality;
  short *av1, *av2, *av3, *au1, *au2, *au3;

  double gain, sum_amps, diff1, diff2, diff3;
  int thresh1, thresh2, thresh3;
  double pha_1to2, pha_2to3, width1, width2;

  progname = strrchr(argv[0], '/');
  if(progname)
    progname++;
  else
    progname = argv[0];

  /* set the default input parameters */
  gain = GAIN;
  thresh1 = THRESH1;
  thresh2 = THRESH2;
  thresh3 = THRESH3;
  pha_1to2 = PHA_1TO2;
  pha_2to3 = PHA_2TO3;
  width1 = WIDTH1;
  width2 = WIDTH2;


  /* check for command line variables */
  while ((c = getopt(argc, argv, "i:o:g:a:b:c:p:P:t:T:h?")) != EOF)
    {
      switch (c) 
        {
        case 'i':
	  inname = optarg;
	  break;
        case 'o':
	  outname = optarg;
	  break;
        case 'g':
          gain = atof(optarg);
          break;
        case 'a':
          thresh1 = atoi(optarg);
          break;
        case 'b':
          thresh2 = atoi(optarg);
          break;
        case 'c':
          thresh3 = atoi(optarg);
          break;
        case 't':
          width1 = atof(optarg);
          break;
        case 'T':
          width2 = atof(optarg);
          break;
        case 'p':
          pha_1to2 = atof(optarg);
          break;
        case 'P':
          pha_2to3 = atof(optarg);
          break;
        case 'h':
        case '?':
          fprintf(stderr,"\nUsage: %s -i infile -o outfile -[abcpPtTh]",
		  progname);
          fprintf(stderr,"\n\t-i infile:\tinput evt0.fits file");
          fprintf(stderr,"\n\t-o outfile:\toutput evt0.fits file");
	  fprintf(stderr,"\n\tg[%.1f]:\tgain for PHA to SUMAMPS", GAIN);
          fprintf(stderr,"\n\ta[%d]:\tscale 1 threshold", THRESH1);
          fprintf(stderr,"\n\tb[%d]:\tscale 2 threshold", THRESH2);
          fprintf(stderr,"\n\tc[%d]:\tscale 3 threshold", THRESH3);
	  fprintf(stderr,"\n\tp[%.1f]:\tPHA for scale 1 to 2 switch", 
		  PHA_1TO2);
	  fprintf(stderr,"\n\tP[%.1f]:\tPHA for scale 2 to 3 switch", 
		  PHA_2TO3);
	  fprintf(stderr,"\n\tt[%.1f]:\t+/- band on PHA scale 1 to 2 switch", 
		  WIDTH1);
	  fprintf(stderr,"\n\tT[%.1f]:\t+/- band on PHA scale 2 to 3 switch", 
		  WIDTH2);
          fprintf(stderr,"\n\th or ?:\tprint usage\n");
          exit(0);
        }
    }

  /* open existing FITS file */
  if (fits_open_file(&infile, inname, READONLY, &status))
    printerror( status );           /* call printerror if error occurs */

  /* determine number of HDUs in input file */
  if (fits_get_num_hdus(infile, &hdunum, &status))
    printerror( status );

  /* create new FITS file */
  if (fits_create_file(&outfile, outname, &status))
    printerror( status );           /* call printerror if error occurs */

  /* copy primary HDU */
  if (fits_copy_hdu( infile, outfile, 0, &status))
    printerror( status );           /* call printerror if error occurs */

  /* Update the DATE keyword in the output file and update the checksums */
  fits_write_date(outfile, &status);
  fits_write_chksum(outfile, &status);

  /* cycle through the FITS extensions */
  for ( kk = 2; kk < hdunum+1; kk++ )
    {
      /* Move to the next extension of input file */
      if (fits_movabs_hdu(infile, kk, &hdutype, &status))
        {
          fits_report_error(stderr, status);
          exit(1);
        }

      /* copy the extension */
      if (fits_copy_hdu( infile, outfile, 0, &status))
	printerror( status );           /* call printerror if error occurs */

      /* Get EXTNAME keyword value to see if this is an events extension */
      if (fits_read_key(infile, TSTRING, "EXTNAME", &extname, comment, 
			&status))
        {
          fits_report_error(stderr, status);
          exit(1);
        }

      if ( !(strcmp(extname,"EVENTS") ))
        {

	  if( fits_read_key(infile, TINT, "TFIELDS", &tfields, NULL, &status) )
	    printerror( status );

	  ttype = CALLOC(tfields, char*);
	  tform = CALLOC(tfields, char*);
	  tunit = CALLOC(tfields, char*);

	  for( i = 0; i < tfields; i++ )
	    {
	      ttype[i] = CALLOC(FLEN_VALUE, char);
	      tform[i] = CALLOC(10, char);
	      tunit[i] = CALLOC(FLEN_VALUE, char);
	    }


          /* we have an EVENTS extension */
	  /* read binary table header keywords */
	  if( fits_read_btblhdr(infile, maxdim, &nrows, &tfields, ttype, 
				tform, tunit, extname, &pcount, &status) ) 
	    printerror( status );

	  fits_get_colnum(infile, CASEINSEN, "AMP_SF", &sf_colnum , &status);
	  fits_get_colnum(infile, CASEINSEN, "AU1", &au1_colnum , &status);
	  fits_get_colnum(infile, CASEINSEN, "AU2", &au2_colnum , &status);
	  fits_get_colnum(infile, CASEINSEN, "AU3", &au3_colnum , &status);
	  fits_get_colnum(infile, CASEINSEN, "AV1", &av1_colnum , &status);
	  fits_get_colnum(infile, CASEINSEN, "AV2", &av2_colnum , &status);
	  fits_get_colnum(infile, CASEINSEN, "AV3", &av3_colnum , &status);
	  fits_get_colnum(infile, CASEINSEN, "PHA", &pha_colnum , &status);

	  /* get number of rows that can be read into memory at once */
	  fits_get_rowsize(infile, &numrows, &status);

	  amp_sf = CALLOC(numrows, unsigned char);
	  pha = CALLOC(numrows, unsigned char);
	  au1 = CALLOC(numrows, short);
	  au2 = CALLOC(numrows, short);
	  au3 = CALLOC(numrows, short);
	  av1 = CALLOC(numrows, short);
	  av2 = CALLOC(numrows, short);
	  av3 = CALLOC(numrows, short);

	  i = 1;
	  while (i <= nrows)
	    {
	      if( i+numrows < nrows )
		i_numrows = numrows;
	      else
 		i_numrows = 1 + nrows - i;

	      if( fits_read_col(infile, TBYTE, sf_colnum, i, 1, i_numrows, 
				&snull, amp_sf, &anynull, &status) )
		printerror( status );
	      if( fits_read_col(infile, TSHORT, au1_colnum, i, 1, i_numrows, 
				&snull, au1, &anynull, &status) )
		printerror( status );
	      if( fits_read_col(infile, TSHORT, au2_colnum, i, 1, i_numrows, 
				&snull, au2, &anynull, &status) )
		printerror( status );
	      if( fits_read_col(infile, TSHORT, au3_colnum, i, 1, i_numrows, 
				&snull, au3, &anynull, &status) )
		printerror( status );
	      if( fits_read_col(infile, TSHORT, av1_colnum, i, 1, i_numrows, 
				&snull, av1, &anynull, &status) )
		printerror( status );
	      if( fits_read_col(infile, TSHORT, av2_colnum, i, 1, i_numrows, 
				&snull, av2, &anynull, &status) )
		printerror( status );
	      if( fits_read_col(infile, TSHORT, av3_colnum, i, 1, i_numrows, 
				&snull, av3, &anynull, &status) )
		printerror( status );
	      if( fits_read_col(infile, TBYTE, pha_colnum, i, 1, i_numrows, 
				&snull, pha, &anynull, &status) )
		printerror( status );

	      /* determine a better AMP_SF value */
	      for( j = 0; j < i_numrows; j++ )
		{
		  if( pha[j] < (pha_1to2 - width1))
		    {
		      amp_sf[j] = 1;
		    }
		  else if(pha[j] < (pha_1to2 + width1))
		    {
		      sum_amps = 
			(double)(au1[j]+au2[j]+au3[j]+av1[j]+av2[j]+av3[j])*0.5
			/gain;
		      diff1 = fabs((double)pha[j] - sum_amps);
		      diff2 = fabs((double)pha[j] - 2.0*sum_amps);
		      if( (diff1 <= diff2) && (diff1 < thresh1) ) 
			{
			  amp_sf[j] = 1;
			} 
		      if((diff2 <= diff1) &&  (diff2 < thresh2))
			{
			  amp_sf[j] = 2;
			} 
		    }
		  else if(pha[j] < (pha_2to3 - width2))
		    {
		      amp_sf[j] = 2;
		    }
		  else if(pha[j] < (pha_2to3 + width2))
		    {
		      sum_amps = 
			(double)(au1[j]+au2[j]+au3[j]+av1[j]+av2[j]+av3[j])*0.5
			/gain;
		      diff2 = fabs((double)pha[j] - 2.0*sum_amps);
		      diff3 = fabs((double)pha[j] - 4.0*sum_amps);
		      if((diff2 <= diff3) && (diff2 < thresh2))
			{
			  amp_sf[j] = 2;
			}
		      if((diff3 <= diff2) && (diff3 < thresh3))
			{
			  amp_sf[j] = 3;
			}
		    }
		  else
		    {
		      amp_sf[j] = 3;
		    }
		}

	      /* write the corrected AMP_SF values to the output file */
	      if( fits_write_col(outfile, TBYTE, sf_colnum, i, 1, i_numrows,
				 amp_sf, &status) )
		printerror( status );
	      i += numrows;
	    }
	}
      if ( fits_write_date(outfile, &status) ) printerror( status );
      if ( fits_write_chksum(outfile, &status) ) printerror( status );
    }
  if ( fits_close_file(infile, &status) ) printerror( status );         
  if ( fits_close_file(outfile, &status) ) printerror( status );

  return 0;
}
