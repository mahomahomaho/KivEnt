import json
import os
import signal

from kivy.logger import Logger
from kivy.vector import Vector


def bisect_iter(ilist):
    if len(ilist) <= 2:
        for x in ilist:
            yield x
        return
    
    mid = int(len(ilist)/2)
    yield ilist[mid]

    for x in bisect_iter(ilist[:mid]):
        yield x

    for x in bisect_iter(ilist[mid + 1:]):
        yield x

def uniq(plist):
    ret = []
    for x in plist:
        if x not in ret:
            ret.append(x)
    return ret


def cross(v1, v2):
    return v1.x*v2.y - v1.y*v2.x
    
def area(verts):
    area = 0.0
    for v1,v2,v3 in zip(verts, verts[1:] + verts[:1], verts[2:] + verts[:2]):
        vec1 = Vector(v2) - Vector(v1)
        vec2 = Vector(v3) - Vector(v2)

        area += cross(vec1, vec2)
    return area

def fix_winding(verts):

    poly_area = area(verts)

    if poly_area < 0:
        return verts
    else:
        return verts[::-1]

def is_convex(verts):
    for v1,v2,v3 in zip(verts, verts[1:] + verts[:1], verts[2:] + verts[:2]):
        vec1 = Vector(v2) - Vector(v1)
        vec2 = Vector(v3) - Vector(v2)

        cr = cross(vec1, vec2)
        if cr == 0 and vec1.dot(vec2) < 0:
            return False
        if cross(vec1, vec2) > 0:
            return False

    return True

def split_path(path, vertsplit):
    left = path[:vertsplit]
    right = path[vertsplit-1:] + [path[0]]

    if hasattr(split_path, 'debug'):
        gnuplot_verts(path, left, right)

    return left, right

def point_in_poly(verts, point):
    #vectors of path
    vertpairs = zip(verts, verts[1:] + verts[:1])
    
    side = None
    for vert1, vert2 in vertpairs:
        vec1 = Vector(vert2) - Vector(vert1)
        vec2 = Vector(point) - Vector(vert1)
        vec1xvec2 = cross(vec1, vec2)
        if vec1xvec2 == 0:
            continue

        if side is None:
            side = vec1xvec2

        if side < 0 and vec1xvec2 > 0:
            return False

        if side > 0 and vec1xvec2 < 0:
            return False
    
    return True

    

def intersects_with_remaining(path, remaining):

    for rv in bisect_iter(remaining[1:-1]):
        if point_in_poly(path, rv):
            return True
    return False

    
def signaltrace(signal, frame):
    import pudb;pudb.set_trace()#TODO:FIXME:DEBUG:remove this breakpoint

def concave2convex(path, desired_area=0.1, min_area=0.01):

    path = uniq(path)
    path_area = area(path)

    desired_area *= path_area
    min_area *= path_area
    
    path = fix_winding(path)

    rotate_cnt = 0
    while True:
        lgpiece = None
        lgremain = None
        lgarea = 0
        if is_convex(path):
            yield path
            return
        for splitvert in range(3, len(path)):
            piece, remaining = split_path(path, splitvert)
            piece_is_convex = is_convex(piece)
            if piece_is_convex and is_convex(remaining):
                yield piece
                yield remaining
                return
            if not piece_is_convex or intersects_with_remaining(piece, remaining):
                if not lgpiece or not lgremain or lgarea > -desired_area:
                    #rotate path
                    rotate_cnt+=1
                    Logger.debug("rotate path no %s", rotate_cnt)
                    path = path[1:] + path[:1]
                    if rotate_cnt >= len(path):
                        desired_area /= 2
                        Logger.debug("desired area is now %s", desired_area)
                        if desired_area <= min_area:
                            Logger.debug("which is below minimum, exiting")
                            return
                        rotate_cnt = 0
                    break
                yield lgpiece
                path = lgremain
                break
            lgpiece = piece
            lgremain = remaining
            lgarea = area(lgpiece)

def cached_c2c(path, cache_dir=".convexpolys", **kwargs):
    pathhash = str(hash(tuple(path + kwargs.items())))
    fname = os.path.join(cache_dir, pathhash)
    try:
        fp = open(fname, "r")
        return json.load(fp)
    except IOError:
        try: 
            os.makedirs(cache_dir)
        except OSError:
            if not os.path.isdir(cache_dir):
                raise
        fp = open(fname, "w")
        ret = list(concave2convex(path, **kwargs))
        json.dump(ret, fp)
        fp.close()
        return ret


if __name__ == '__main__':
    from debugdraw import gnuplot_verts

    for x in concave2convex([(0,0), (0,2), (1,1), (2,2), (2,0), (1, 0.5)]):
        gnuplot_verts(x)

            







