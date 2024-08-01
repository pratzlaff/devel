import numpy as np
import pyfits
import argparse

def update_spectrum( outfile, splicefile, mlam_lo, mlam_hi ):
    hdulist1 = pyfits.open( outfile, mode='update', memmap=True )
    hdulist2 = pyfits.open( splicefile, memmap=True )

    data1 = hdulist1['spectrum'].data
    data2 = hdulist2['spectrum'].data

    np.testing.assert_array_equal( data1.field('tg_m'), data2.field('tg_m') )
    np.testing.assert_array_equal( data1.field('bin_lo'), data2.field('bin_lo') )
    np.testing.assert_array_equal( data1.field('bin_hi'), data2.field('bin_hi') )

    tg_m = data1.field('tg_m')[:,np.newaxis]

    mlam1 = data1.field('bin_lo') * tg_m
    mlam2 = data1.field('bin_hi') * tg_m

    for i in range( tg_m.shape[0] ):
        mask = ( mlam1[i,:] >= mlam_lo ) & ( mlam2[i,:] <= mlam_hi )
        data1.field('counts')[i,mask] = data2.field('counts')[i,mask]
        data1.field('stat_err')[i,mask] = data2.field('stat_err')[i,mask]

        print("overwriting %d channels for spectrum number %d, order = %d" % ( np.sum(mask), data1.field('spec_num')[i], data1.field('tg_m')[i] ) )

    hdulist1.close()
    hdulist2.close()

def main():

    parser = argparse.ArgumentParser()
    parser.add_argument('outfile', help='spectrum to be overwritten')
    parser.add_argument('splicefile', help='spectrum from which splice will be taken')
    parser.add_argument('mlam_lo', help='low mlam limit for splice', type=float)
    parser.add_argument('mlam_hi', help='high mlam limit for splice', type=float)
    args = parser.parse_args()

    assert args.mlam_lo < args.mlam_hi

    update_spectrum( args.outfile, args.splicefile, args.mlam_lo, args.mlam_hi )

if __name__ == '__main__':
    main()
