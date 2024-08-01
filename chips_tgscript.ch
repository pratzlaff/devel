# Time-stamp: <2000-12-19 11:36:14 dph> 
# MIT Directory: ~dph/h3/CXC/TG/AGfCHRS/Sl/
# CfA Directory: /dev/null
# File: chips_tgscript.ch
# Author: D. Huenemoerder
# Original version: 2000.12.18
#====================================================================

# This is an example of how to make a few diagnostic plots of 
# grating event files.  The file is a series of chips commands, and
# requires one Slang file, which contains several utility functions.
# To try this, define f_evt and f_get to point to and event file and
# the Slang file.

# The slang functions are not very sophisticated.  They do no error
# checking, nor are they very generic (specificer is quicker)
# They do demonstrate the use of multiple-return values.
# As a matter of taste, I always terminate Slang statements with a
# ";".  That is not required by chips, unless you have multiple
# statements per line.

#  This example is for HETG/ACIS-S.  With small modifications, it
#  would also work for LETG/HRC-S or LETG/ACIS-S.
#
# There are some shell commands to convert the postscript output to
# png format.  These require you to have the pbmplus utilities in your
# path.  If you are happy with (possibly enormous) postcript files,
# you can comment-out the shell escapes.
########################################################################

f_evt="/data/anto/jeremy/uxari/acisf00605N002_evt2.fits"
f_get="/data/anto/jeremy/get_evt_data.sl"


e=readfile(f_evt);
r=readfile(f_evt+"[REGION]");

evalfile(f_get);

# plot the sky field, and color in the regions.  Overplot the
# HEG, MEG and zero-order regions from the region extension.

## get event arrays for different tg_part:

(xm,ym)=get_evt_part(e,2,"sky");  
(xh,yh)=get_evt_part(e,1,"sky");
(xz,yz)=get_evt_part(e,0,"sky");
(xo,yo)=get_evt_part(e,99,"sky");

## get region arrays:

## zero-order region, % HEG box,   % MEG box
(xzo,yzo)=reg_cir_toxy(r,0); 
(xbh,ybh)=reg_box_toxy(r,1);    
(xbm,ybm)=reg_box_toxy(r,2);  

redraw off
pack on

curve x xo y yo
curve x xm y ym
curve x xh y yh
curve x xz y yz

curve x xzo y yzo
curve x xbm y ybm
curve x xbh y ybh

# 1:other, 2:MEG  3:HEG  4:ZO   5:ZOreg   6: MEGreg  7:HEGreg
c 1 symbol size 0.1
c 2 symbol size 0.1
c 3 symbol size 0.1
c 4 symbol size 0.1
c 5 symbol size 0.1
c 6 symbol size 0.1
c 7 symbol size 0.1

c 2 symbol red     
c 3 symbol green   
c 4 symbol blue    

c 5 curve simpleline
c 6 curve simpleline
c 7 curve simpleline

c 5 curve yellow  
c 6 curve magenta 
c 7 curve cyan    

xlabel "sky x [pixel]"
ylabel "sky y [pixel]"
title "Sky field view"

#limits auto auto auto auto
limits 1000 7000 1000 7000
redraw

print postfile Sky_xy.ps

## zoom on zero order

limits 3600 4600 3600 4600
redraw

print postfile Sky_xy_zoom.ps

##############  Look at the events in diffraction coordinates, tg_lam, tg_d

## MEG

redraw off

c 1 del
c 2 del
c 3 del
c 4 del
d 1 del

clear
redraw

(xm,ym) = get_evt_part_order(e, 2, 1, "tglam");

curve x xm y ym
c 1 symbol size .1
limits auto auto -0.002 0.002

xlabel "Wavelength [Angstrom]"
ylabel "tg_d [degrees]"
title "MEG part photons, +-1st order"

redraw
print postfile MEG_lamd.ps

## HEG

c 1 del
d 1 del

clear
redraw

(xh,yh) = get_evt_part_order(e, 1, 1, "tglam");
curve x xh y yh
c 1 symbol size .1
limits auto auto -0.002 0.002

xlabel "Wavelength [Angstrom]"
ylabel "tg_d [degrees]"
title "HEG part photons, +-1st orders"

redraw

print postfile HEG_lamd.ps


##### Look at events in order-ratio plots; color by order to see the
##### order-sorting boundiaries imposed by the osip file:

d 1 del
clear
redraw

### MEG
(xm1,ym1) = get_evt_part_order(e, 2, 1, "tgmlamccd");
(xm2,ym2) = get_evt_part_order(e, 2, 2, "tgmlamccd");
(xm3,ym3) = get_evt_part_order(e, 2, 3, "tgmlamccd");
(xmo,ymo) = get_evt_part(e, 2, "tgmlamccd");

yy1=abs(xm1/ym1)
yy2=abs(xm2/ym2)
yy3=abs(xm3/ym3)
yyo=abs(xmo/ymo)

curve x xmo y yyo
curve x xm1 y yy1
curve x xm2 y yy2
curve x xm3 y yy3

c 1 symbol size .1
c 2 symbol size .1
c 3 symbol size .1
c 4 symbol size .1

c 2 symbol red
c 3 symbol green
c 4 symbol blue

limits -30 30 0 5

xlabel "Wavelength*order [Angstrom]"
ylabel "abs(order)~abs(tg_mlam)/ccd_lam [1]"
title "MEG part photons, order-sorting"

redraw
print postfile MEG_osort.ps

############ HEG order-sorting
d 1 del
clear
redraw

(xh1,yh1) = get_evt_part_order(e, 1, 1, "tgmlamccd");
(xh2,yh2) = get_evt_part_order(e, 1, 2, "tgmlamccd");
(xh3,yh3) = get_evt_part_order(e, 1, 3, "tgmlamccd");
(xho,yho) = get_evt_part(e, 1, "tgmlamccd");

yy1=abs(xh1/yh1)
yy2=abs(xh2/yh2)
yy3=abs(xh3/yh3)
yyo=abs(xho/yho)

curve x xho y yyo
curve x xh1 y yy1
curve x xh2 y yy2
curve x xh3 y yy3

c 1 symbol size .1
c 2 symbol size .1
c 3 symbol size .1
c 4 symbol size .1

c 2 symbol red
c 3 symbol green
c 4 symbol blue

limits -15 15 0 5

xlabel "Wavelength*order [Angstrom]"
ylabel "abs(order)~abs(tg_mlam)/ccd_lam [1]"
title "HEG part photons, order-sorting"

redraw

print postfile HEG_osort.ps




