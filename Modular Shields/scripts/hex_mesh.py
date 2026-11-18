"""Build a closed dual-icosphere with cell-edge coordinates, without UV wrapping.

SCM v5 layout reference: Oygron/SupCom_Import_Export_Blender, scm_vertex/scm_bone.
No game mesh data is copied. Radius is 0.5, matching FAF shield draw scales.
"""
import itertools
import math
import struct
from collections import Counter


def add(a, b):
    return tuple(x+y for x, y in zip(a, b))


def sub(a, b):
    return tuple(x-y for x, y in zip(a, b))


def dot(a, b):
    return sum(x*y for x, y in zip(a, b))


def cross(a, b):
    return (a[1]*b[2]-a[2]*b[1], a[2]*b[0]-a[0]*b[2], a[0]*b[1]-a[1]*b[0])


def unit(v):
    length = math.sqrt(dot(v, v))
    return tuple(x/length for x in v)


def generate(path):
    phi = (1+math.sqrt(5))/2
    points = [unit(v) for v in
              [(0,a,b*phi) for a in (-1,1) for b in (-1,1)] +
              [(a,b*phi,0) for a in (-1,1) for b in (-1,1)] +
              [(b*phi,0,a) for a in (-1,1) for b in (-1,1)]]
    faces = []
    for a,b,c in itertools.combinations(range(12), 3):
        if max(dot(sub(points[i],points[j]),sub(points[i],points[j]))
               for i,j in ((a,b),(b,c),(c,a))) < 1.11:
            if dot(cross(sub(points[b],points[a]),sub(points[c],points[a])),points[a]) < 0:
                b,c = c,b
            faces.append((a,b,c))
    assert len(faces) == 20
    for _ in range(3):
        midpoints = {}
        def midpoint(a,b):
            key = tuple(sorted((a,b)))
            if key not in midpoints:
                midpoints[key] = len(points)
                points.append(unit(add(points[a],points[b])))
            return midpoints[key]
        refined = []
        for a,b,c in faces:
            ab,bc,ca = midpoint(a,b),midpoint(b,c),midpoint(c,a)
            refined.extend(((a,ab,ca),(ab,b,bc),(ca,bc,c),(ab,bc,ca)))
        faces = refined
    # Gentle spherical relaxation reduces the area variation of projected ico cells.
    neighbors = [set() for _ in points]
    for a,b,c in faces:
        for i,j in ((a,b),(b,c),(c,a)):
            neighbors[i].add(j);neighbors[j].add(i)
    for _ in range(40):
        points = [unit(add(p,unit(tuple(sum(points[j][k] for j in ns)/len(ns)
                                             for k in range(3)))))
                  for p,ns in zip(points,neighbors)]
    corners = []
    cells = [[] for _ in points]
    for index,(a,b,c) in enumerate(faces):
        corner = unit(cross(sub(points[b],points[a]),sub(points[c],points[a])))
        if dot(corner,points[a]) < 0:
            corner = tuple(-x for x in corner)
        corners.append(corner)
        for i in (a,b,c): cells[i].append(index)
    assert Counter(map(len,cells)) == {5:12,6:630}
    edges = Counter()
    vertices,indices = [],[]
    for p,cell in zip(points,cells):
        tangent = unit(cross(p,(0,1,0) if abs(p[1]) < .9 else (1,0,0)))
        bitangent = cross(p,tangent)
        cell.sort(key=lambda i: math.atan2(dot(corners[i],bitangent),dot(corners[i],tangent)))
        for a,b in zip(cell,cell[1:]+cell[:1]):
            edges[tuple(sorted((a,b)))] += 1
            base = len(vertices)
            for n,edge in ((p,0),(corners[a],1),(corners[b],1)):
                # position, normal, tangent, binormal, UV0, UV1, bone indices
                vertices.append(struct.pack('<16f4B',*(tuple(x*.5 for x in n)+n+
                                tangent+bitangent+(edge,0,0,0)),0,0,0,0))
            indices.extend((base,base+1,base+2))
    assert set(edges.values()) == {2}, 'Every cell border must meet exactly two cells'
    assert len(vertices) < 65536
    # Header, name section and single identity root bone; align sections to 16 bytes.
    prefix = bytearray(192)
    prefix[60:64] = b'NAME'
    prefix[64:72] = b'HexDome\0'
    prefix[76:80] = b'SKEL'
    identity = (1,0,0,0,0,1,0,0,0,0,1,0,0,0,0,1)
    struct.pack_into('<16f3f4f4i',prefix,80,*identity,0,0,0,1,0,0,0,64,-1,0,0)
    prefix[188:192] = b'VRTX'
    vertex_data = b''.join(vertices)
    padding = b'\0' * ((-len(vertex_data)-4) % 16)
    index_offset = len(prefix)+len(vertex_data)+len(padding)+4
    struct.pack_into('<4s11I',prefix,0,b'MODL',5,80,1,192,0,len(vertices),index_offset,len(indices),0,0,1)
    data = prefix+vertex_data+padding+b'TRIS'+struct.pack('<%dH'%len(indices),*indices)
    assert len(prefix) == 192 and index_offset % 16 == 0
    assert data[index_offset-4:index_offset] == b'TRIS'
    # Round-trip the emitted binary, including vertex radius and index bounds.
    for i in range(len(vertices)):
        p = struct.unpack_from('<3f',data,192+i*68)
        assert abs(dot(p,p)-.25) < 1e-6
    assert max(struct.unpack_from('<%dH'%len(indices),data,index_offset)) < len(vertices)
    path.write_bytes(data)
    print(f'PASS: closed geodesic SCM: 630 hexagons, 12 pentagons, {len(indices)//3} triangles')
