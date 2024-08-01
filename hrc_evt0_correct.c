/*
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
            hrc_evt0_correct
	    M. Juda
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

$Id: hrc_evt0_correct.c,v 1.9 2002/01/08 20:45:21 juda Exp $

Corrects tap data for events that are affected by the hardware "ringing" 
problem (e.g. events with amp_sf = 3, a1 > a3, and a1 > const1*a2+const2).

*/

/*** include files ***/
#include <stdio.h>
#include <string.h>
#include <math.h>

#include "fitsio.h"

#include "correction.h"

#define RCS "$Revision: 1.9 $\n"

extern int optind;
extern char *optarg;

int getopt();
int atoi();
double atof();

int print_usage(char *progname)
{
  fprintf(stderr, RCS);

  fprintf(stderr, 
	  "\nUsage:\n\t%s [-abcdefgoABCDEFGOv] <HRC_L0_EVENTS> <HRC_L0_EVENTS>\n", 
	  progname);
  fprintf(stderr,"\ta[%.3f]:\tu-axis sinusoid amplitude 'slope'\n",
	  UAXIS_A);
  fprintf(stderr,"\tb[%.3f]:\tu-axis sinusoid amplitude intercept\n",
	  UAXIS_B);
  fprintf(stderr,"\tc[%.3f]:\tu-axis sinusoid period slope\n",
	  UAXIS_C);
  fprintf(stderr,"\td[%.3f]:\tu-axis sinusoid period intercept\n",
	  UAXIS_D);
  fprintf(stderr,"\te[%.3f]:\tAU1/AU2 limit slope for correction\n",
	  UAXIS_E);
  fprintf(stderr,"\tf[%.3f]:\tAU1/AU2 phase shift amplitude\n",
	  UAXIS_F);
  fprintf(stderr,"\tg[%.3f]:\tAU1/AU2 phase shift power\n",
	  UAXIS_G);
  fprintf(stderr,"\to[%.3f]:\tAU1/AU2 limit offset for correction\n",
	  UAXIS_O);

  fprintf(stderr,"\tA[%.3f]:\tv-axis sinusoid amplitude 'slope'\n",
	  VAXIS_A);
  fprintf(stderr,"\tB[%.3f]:\tv-axis sinusoid amplitude intercept\n",
	  VAXIS_B);
  fprintf(stderr,"\tC[%.3f]:\tv-axis sinusoid period slope\n",
	  VAXIS_C);
  fprintf(stderr,"\tD[%.3f]:\tv-axis sinusoid period intercept\n",
	  VAXIS_D);
  fprintf(stderr,"\tE[%.3f]:\tAV1/AV2 limit slope for correction\n",
	  VAXIS_E);
  fprintf(stderr,"\tF[%.3f]:\tAV1/AV2 phase shift amplitude\n",
	  VAXIS_F);
  fprintf(stderr,"\tG[%.3f]:\tAV1/AV2 phase shift power\n",
	  VAXIS_G);
  fprintf(stderr,"\tO[%.3f]:\tAV1/AV2 limit offset for correction\n",
	  VAXIS_O);

  fprintf(stderr,"\tw:\tuse width-exceeded bits to ID events\n");

  fprintf(stderr,"\tv[0]:\tverbosity of diagnostic output\n");
  fprintf(stderr,"\th or ?:\tprint usage\n");
  return 0;
}

/*============================================================*/
int main(argc,argv)
int argc;
char *argv[];

{
  int c, verb = 0, ii, jj, kk, ncycle, use_width, correct;
  char *progname, *inname, *outname;
  double uaxis_a, uaxis_b, uaxis_c, uaxis_d, uaxis_e, uaxis_f, uaxis_g, 
    uaxis_o;
  double vaxis_a, vaxis_b, vaxis_c, vaxis_d, vaxis_e, vaxis_f, vaxis_g, 
    vaxis_o;
  double a1, a2, a3, phi;

  /* ============== FITSIO variables ================== */

  fitsfile *infile, *outfile;

  int hdunum, hdutype, status = 0;
  long nevents;
  long nrows, numrows, init_row;
  char extname[FLEN_VALUE];
  char comment[FLEN_COMMENT];

  short *snull = 0;
  unsigned char *bnull = 0;
  int ncols, colnum, *anynull = 0;

  /* data from essential level 0 events columns */
  unsigned char *ampsf, *vstat;
  short *av1, *av2, *av3, *au1, *au2, *au3;

  /* Initialize command correction coefficients */
  uaxis_a = UAXIS_A;
  uaxis_b = UAXIS_B;
  uaxis_c = UAXIS_C;
  uaxis_d = UAXIS_D;
  uaxis_e = UAXIS_E;
  uaxis_f = UAXIS_F;
  uaxis_g = UAXIS_G;
  uaxis_o = UAXIS_O;
  vaxis_a = VAXIS_A;
  vaxis_b = VAXIS_B;
  vaxis_c = VAXIS_C;
  vaxis_d = VAXIS_D;
  vaxis_e = VAXIS_E;
  vaxis_f = VAXIS_F;
  vaxis_g = VAXIS_G;
  vaxis_o = VAXIS_O;
  use_width = 0;

  progname = strrchr(argv[0], '/');
  if(progname)
    progname++;
  else
    progname = argv[0];

  /* check for command line variables */
  while ((c = getopt(argc, argv, "a:b:c:d:e:f:g:o:A:B:C:D:E:F:G:O:v:wh?")) != EOF)
    {
      switch (c) 
        {
        case 'a':
	  uaxis_a = atof(optarg);
          break;
        case 'b':
	  uaxis_b = atof(optarg);
          break;
        case 'c':
	  uaxis_c = atof(optarg);
          break;
        case 'd':
	  uaxis_d = atof(optarg);
          break;
        case 'e':
	  uaxis_e = atof(optarg);
          break;
        case 'f':
	  uaxis_f = atof(optarg);
          break;
        case 'g':
	  uaxis_g = atof(optarg);
          break;
        case 'o':
	  uaxis_o = atof(optarg);
          break;
        case 'A':
	  vaxis_a = atof(optarg);
          break;
        case 'B':
	  vaxis_b = atof(optarg);
          break;
        case 'C':
	  vaxis_c = atof(optarg);
          break;
        case 'D':
	  vaxis_d = atof(optarg);
          break;
        case 'E':
	  vaxis_e = atof(optarg);
          break;
        case 'F':
	  vaxis_f = atof(optarg);
          break;
        case 'G':
	  vaxis_g = atof(optarg);
          break;
        case 'O':
	  vaxis_o = atof(optarg);
          break;
        case 'v':
	  verb = atoi(optarg);
          break;
        case 'w':
	  use_width = 1;
          break;
        case 'h':
        case '?':
	  print_usage(progname);
	  exit(0);
        }
    }

  if( argc < 3 )
    {
      print_usage(progname);
      exit(1);
    }


  if(verb > 0) fprintf(stderr, "\n\n***** Running %s *****\n\t", progname);
  if(verb > 0) fprintf(stderr, RCS);

  inname = argv[argc-2];
  outname = argv[argc-1];

  /* open input FITS file */
  if(verb > 0) fprintf(stderr, "\nInput file:  %s\n", inname);
  if (fits_open_file(&infile, inname, READONLY, &status))
    {
      fits_report_error(stderr, status);
      exit(1);
    }
  fits_get_num_hdus(infile, &hdunum, &status);
  if(verb > 0) 
    fprintf(stderr, "Input file has %d Header-Data units\n", hdunum);

  /* open output FITS file */
  if(verb > 0) fprintf(stderr, "Output file: %s\n", outname);
  if (fits_create_file(&outfile, outname, &status))
    {
      fits_report_error(stderr, status);
      exit(1);
    }

  if(verb > 0) fprintf(stderr, "Copy Primary HDU to output file\n");
  /* Copy primary HDU from input to output file */  
  if (fits_copy_hdu(infile, outfile, 0, &status))
    {
      fits_report_error(stderr, status);
      exit(1);
    }

  /* Update the DATE keyword in the output file and update the checksums */
  if(verb > 0) fprintf(stderr, "Update DATE and Checksums\n");
  fits_write_date(outfile, &status);
  fits_write_chksum(outfile, &status);

  if(verb > 0) fprintf(stderr, "Move on to extensions\n");
  for ( kk = 2; kk < hdunum+1; kk++ )
    {
      /* Move to the next extension of input file */
      if (fits_movabs_hdu(infile, kk, &hdutype, &status))
	{
	  fits_report_error(stderr, status);
	  exit(1);
	}
      if(verb > 0) fprintf(stderr, "Extension %d\n", kk-1);

      /* Get EXTNAME keyword value to see if this is an events extension */
      if (fits_read_key(infile, TSTRING, "EXTNAME", extname, comment, &status))
	{
	  fits_report_error(stderr, status);
	  exit(1);
	}
      if(verb > 0) fprintf(stderr, "Extension name: %s\n", extname);

      if ( !(strcmp(extname,"EVENTS") ))
	{
	  /* we have an EVENTS extension */
	  fits_get_num_cols(infile, &ncols, &status);
	  fits_get_num_rows(infile, &nrows, &status);

	  if(verb > 0) fprintf(stderr,"Extension has %d columns and %d rows\n",
			       (int)ncols, (int)nrows);
	  /* Copy HDU from input file to output file */
	  if (fits_copy_hdu(infile, outfile, 0, &status))
	    {
	      fits_report_error(stderr, status);
	      exit(1);
	    }

	  fits_get_rowsize(infile, &numrows, &status);
	  if(verb > 0) fprintf(stderr,"FITSIO optimal buffer %d rows\n", 
			     (int)numrows);

	  if ((numrows/2) > nrows)
	    {
	      nevents = nrows/2;
	    }
	  else
	    {
	      nevents = numrows/2;
	      ncycle = nrows/nevents + 1;
	    }

	  if(verb>0) fprintf(stderr,"Will use %d cycles to process data\n",
			     ncycle);

	  ampsf = CALLOC(nevents, unsigned char);
	  av1 = CALLOC(nevents, short);
	  av2 = CALLOC(nevents, short);
	  av3 = CALLOC(nevents, short);
	  au1 = CALLOC(nevents, short);
	  au2 = CALLOC(nevents, short);
	  au3 = CALLOC(nevents, short);
	  vstat = CALLOC(nevents, unsigned char);

	  if(verb>0) fprintf(stderr,"Internal buffers allocated\n");

	  for( ii = 0; ii < ncycle; ii++ )
	    {
	      init_row = 1 + ii*nevents;
	      if(verb>0) fprintf(stderr,"Cycle: %d - First Row:%d\n", (int)ii,
				 (int)init_row);
	      if( (init_row + nevents) >= nrows ) 
		nevents = 1 + nrows - init_row;

	      fits_get_colnum(infile, CASEINSEN, "AMP_SF", &colnum, 
			      &status);
	      fits_read_col(infile, TBYTE, colnum, init_row, 1, nevents, 
			    bnull, ampsf, anynull, &status);

	      fits_get_colnum(infile, CASEINSEN, "AV1", &colnum, &status);
	      fits_read_col(infile, TSHORT, colnum, init_row, 1, nevents, 
			    snull, av1, anynull, &status);
	      fits_get_colnum(infile, CASEINSEN, "AV2", &colnum, &status);
	      fits_read_col(infile, TSHORT, colnum, init_row, 1, nevents, 
			    snull, av2, anynull, &status);
	      fits_get_colnum(infile, CASEINSEN, "AV3", &colnum, &status);
	      fits_read_col(infile, TSHORT, colnum, init_row, 1, nevents, 
			    snull, av3, anynull, &status);

	      fits_get_colnum(infile, CASEINSEN, "AU1", &colnum, &status);
	      fits_read_col(infile, TSHORT, colnum, init_row, 1, nevents, 
			    snull, au1, anynull, &status);
	      fits_get_colnum(infile, CASEINSEN, "AU2", &colnum, &status);
	      fits_read_col(infile, TSHORT, colnum, init_row, 1, nevents, 
			    snull, au2, anynull, &status);
	      fits_get_colnum(infile, CASEINSEN, "AU3", &colnum, &status);
	      fits_read_col(infile, TSHORT, colnum, init_row, 1, nevents, 
			    snull, au3, anynull, &status);

	      fits_get_colnum(infile, CASEINSEN, "VETOSTT", &colnum, 
			      &status);
	      fits_read_col(infile, TBYTE, colnum, init_row, 1, nevents, 
			    bnull, vstat, anynull, &status);

	      if(verb>0) fprintf(stderr,"Correcting events\n");
	      for( jj = 0; jj < nevents; jj++)
		{
		  if ( ampsf[jj] == 3 )
		    {
		      correct = 0;

		      if ( (au1[jj] > au3[jj]) && (use_width == 0)
			   && (au1[jj] > (uaxis_e * au2[jj] + uaxis_o)) )
			correct = 1;
		      if ( (au1[jj] > au3[jj]) && (use_width != 0)
			   && ((vstat[jj] & 0x10) == 0) )
			correct = 1;

		      if ( correct == 1 )
			{
			  a1 = (double)au1[jj];
			  a2 = (double)au2[jj];
			  a3 = (double)au3[jj];
			  phi = 0.0;
			  if (au1[jj] > 0)
			    phi = uaxis_f*(pow(a2/a1,uaxis_g) - 1.0);
			  a3 = a3 - (a2 + uaxis_b)/uaxis_a
			    * sin(2.*PI*(a2-phi)/(a2*uaxis_c + uaxis_d));
			  au3[jj] = (short)(a3 + 0.5);
			  if(au3[jj] < 0) au3[jj] = 0;
			  if(au3[jj] > 4095) au3[jj] = 4095;
			}

		      correct = 0;

		      if ( (av1[jj] > av3[jj]) && (use_width == 0)
			   && (av1[jj] > (vaxis_e * av2[jj] + vaxis_o)) )
			correct = 1;
		      if ( (av1[jj] > av3[jj]) && (use_width != 0)
				&& ((vstat[jj] & 0x20) == 0) )
			correct = 1;

		      if ( correct == 1 )
			{
			  a1 = (double)av1[jj];
			  a2 = (double)av2[jj];
			  a3 = (double)av3[jj];
			  phi = 0.0;
			  if (av1[jj] > 0)
			    phi = vaxis_f*(pow(a2/a1,vaxis_g) - 1.0);
			  a3 = a3 - (a2 + vaxis_b)/vaxis_a 
			    * sin(2.*PI*(a2-phi)/(a2*vaxis_c + vaxis_d));
			  av3[jj] = (short)(a3 + 0.5);
			  if(av3[jj] < 0) av3[jj] = 0;
			  if(av3[jj] > 4095) av3[jj] = 4095;
			}
		    }
		}

	      fits_get_colnum(infile, CASEINSEN, "AV3", &colnum, &status);
	      fits_write_col(outfile, TSHORT, colnum, init_row, 1, 
			     nevents, av3, &status);
	      fits_get_colnum(infile, CASEINSEN, "AU3", &colnum, &status);
	      fits_write_col(outfile, TSHORT, colnum, init_row, 1, 
			     nevents, au3, &status);

	    }
	}
      else
	{
	  fits_copy_hdu(infile, outfile, 0, &status);
	}
      fits_write_date(outfile, &status);
      fits_write_chksum(outfile, &status);
    }

  fits_close_file(infile, &status);	    
  fits_close_file(outfile, &status);

  return 0;
}
