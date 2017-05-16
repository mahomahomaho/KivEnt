import itertools
from math import ceil, sqrt
import os


def gnuplot_verts(*vss, **kwargs):
    pdf = kwargs.get("pdf", True)
    single = kwargs.get("single", False)
    closed = kwargs.get("closed", True)
    f = open("/tmp/ee.plt", "w")

    minr, maxr = 999999, -9999999
    for path in vss:
        for vert in path:
            for coord in vert:
                minr = min(minr, coord)
                maxr = max(maxr, coord)

    numplots = len(vss)
    inrow = int(ceil(sqrt(numplots)))
    numrows = int(ceil(float(numplots)/inrow))

    if pdf:
        f.write('set terminal pdfcairo font "arial, 9" size 30cm,30cm \n')
        f.write('set output "/tmp/ee.pdf"\n')
    if not single:
        f.write("set multiplot layout %s, %s\n"%(numrows, inrow))
    f.write("set size ratio -1\n")
    if single:
        f.write("plot '-' u 1:2:3:4 w vectors\n")
    for vs in vss:
        
        #f.write("set xrange[%s:%s]\n"%(minr-1, maxr+1))
        #f.write("set yrange[%s:%s]\n"%(minr-1, maxr+1))
        if not single:
            f.write("plot '-' u 1:2:3:4 w vectors\n")
       
        for (fx, fy),(tx, ty) in (zip(vs, vs[1:] + vs[:1]) if closed else zip(vs[:-1], vs[1:])):
            f.write("%s %s %s %s\n"%(fx, fy, (tx-fx), (ty-fy)))
   
        if not single:
            f.write("e\n")
    if single:
        f.write("e\n")

    f.close()
    os.system("gnuplot /tmp/ee.plt -persist")


if __name__ == '__main__':
    gnuplot_verts([(0, 0), (0,1), (1,1), (1, 0)],
                    [(1,1), (2,2), (3,2), (4,0)])
