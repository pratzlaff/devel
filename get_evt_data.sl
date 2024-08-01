% Time-stamp: <2000-12-19 11:36:37 dph> 
% MIT Directory: ~dph/h3/CXC/TG/AGfCHRS/Sl/
% CfA Directory: /dev/null
% File: get_evt_data.sl
% Author: D. Huenemoerder
% Original version: 2000.12.18
%
%====================================================================

% The following are some not-to-clever Slang functions for returning
% data from an event structure.  There is no error checking.
% The functions could be made more intelligent by parsing the file
% contents or headers.  These were written for ad hoc (Latin for "Quick
% and Dirty") demonstration of some fundamental operations.

% Example usage can be found in the chips command script,
% chips_tgscript.ch

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

define get_evt_part(evt, part, coords)
{
 variable idx;
 variable x,y;
 variable pc_hc = 12.39854;    % physical constant, h*c in [keV/A]

 idx = where( evt.tg_part == part );

 if (coords == "sky")
 {
   x = evt.x[idx];
   y = evt.y[idx];
 }
 if (coords == "tglam")
 {
   x = evt.tg_lam[idx];
   y = evt.tg_d[idx];
 }  
 if (coords == "tgmlam")
 {
   x = evt.tg_mlam[idx];
   y = evt.tg_d[idx];
 }  
 if (coords == "tgmlamccd")
 {
   x = evt.tg_mlam[idx];
   y = 1000.*pc_hc/evt.energy[idx];
 }  

 return x,y;

} 
 
define get_evt_part_order(evt, part, order, coords)
{
 variable idx;
 variable x,y;
 variable pc_hc = 12.39854;    % physical constant, h*c in [keV/A]

 idx = where( (evt.tg_part == part ) and ( (evt.tg_m == -order) or (evt.tg_m == order) ) );

 if (coords == "sky")
 {
   x = evt.x[idx];
   y = evt.y[idx];
 }
 if (coords == "tglam")
 {
   x = evt.tg_lam[idx];
   y = evt.tg_d[idx];
 }  
 if (coords == "tgmlam")
 {
   x = evt.tg_mlam[idx];
   y = evt.tg_d[idx];
 }  
 if (coords == "tgmlamccd")
 {
   x = evt.tg_mlam[idx];
   y = 1000.*pc_hc/evt.energy[idx];
 }  

 return x,y;

} 
 

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%  given a FITS spatial region structure, return coords for
%   the region part given by the index.
%  Usually, for HETG, there are 3 parts:
%
%    idx=0 => zero order
%        1 => HEG
%        2 => MEG
%
%  For LETG, 0 is zero order, 1 is LEG.
%  could determine from the file (but I'm lazy)
%  No error checking.  (really lazy)
%  minimally translated to slang from idl rd_tgreg.pro
%  
% (should at least check reg[idx].shape)


define reg_cir_toxy(reg, idx)
{
% region argument can be read via:   reg=readfile(filename_evt2+"[REGION]");

  variable npts=128;
  variable x, y, tt;

  tt=[0:npts-1:1.]/npts *2.*PI;

  x = cos(tt) * reg.r[idx,0] +  reg.x[idx];
  y = sin(tt) * reg.r[idx,0] +  reg.y[idx];

  return x,y;
}


define reg_box_toxy(reg,idx)
{

  variable x, y, crot, srot, xo, yo;

  x = [0., 1., 1., 0., 0.] - 0.5;   % generic x corners, centered unit box
  y = [0., 0., 1., 1., 0.] - 0.5;   % generic y corners, centered unit box

  x = x * reg.r[idx,0];             % scale to length
  y = y * reg.r[idx,1];             % scale to height

  crot = cos(-reg.rotang[idx]*PI/180.);
  srot = sin(-reg.rotang[idx]*PI/180.);

  xo =  x*crot + y*srot + reg.x[idx];
  yo = -x*srot + y*crot + reg.y[idx];

  return xo, yo;

}

