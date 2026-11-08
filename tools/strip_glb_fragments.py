"""Remove floating fragments from a GLB in place (degenerates their triangles).
Connectivity is by welded vertex position, so UV seams don't split parts.
A component is dropped if it holds < MAXF of the faces and lies outside the
main body's bounding box (expanded by PAD of its size).
usage: strip_frags.py [--dry] file.glb ...
"""
import sys, struct, json
import numpy as np
from scipy.sparse import coo_matrix
from scipy.sparse.csgraph import connected_components
from scipy.spatial import cKDTree
MAXF, PAD, GAP = 0.03, 0.02, 0.04  # GAP: min distance to the body, as a fraction of its size
CT = {5121: np.uint8, 5123: np.uint16, 5125: np.uint32, 5126: np.float32}
NC = {'SCALAR': 1, 'VEC2': 2, 'VEC3': 3, 'VEC4': 4}
def acc_view(j, binoff, buf, ai):
    a = j['accessors'][ai]; bv = j['bufferViews'][a['bufferView']]
    off = binoff + bv.get('byteOffset', 0) + a.get('byteOffset', 0)
    dt = CT[a['componentType']]; n = a['count'] * NC[a['type']]
    assert bv.get('byteStride', 0) in (0, np.dtype(dt).itemsize * NC[a['type']])
    return off, np.frombuffer(buf, dt, n, off).reshape(a['count'], NC[a['type']]) if NC[a['type']] > 1 else np.frombuffer(buf, dt, n, off)
dry = '--dry' in sys.argv
only_main = '--only-main' in sys.argv  # keep just the largest connected part
for p in [x for x in sys.argv[1:] if not x.startswith('--')]:
    b = bytearray(open(p, 'rb').read())
    jl = struct.unpack('<I', b[12:16])[0]; j = json.loads(b[20:20 + jl])
    binoff = 20 + jl + 8
    report = []
    changed_json = False
    for m in j['meshes']:
        for pr in m['primitives']:
            _, pos = acc_view(j, binoff, b, pr['attributes']['POSITION'])
            ioff, idx = acc_view(j, binoff, b, pr['indices'])
            tri = idx.reshape(-1, 3).astype(np.int64)
            q = np.round(pos / (np.ptp(pos, 0).max() * 1e-4)).astype(np.int64)
            _, weld = np.unique(q, axis=0, return_inverse=True); weld = weld.ravel()
            t = weld[tri]; nv = weld.max() + 1
            r = np.concatenate([t[:, 0], t[:, 1]]); c = np.concatenate([t[:, 1], t[:, 2]])
            g = coo_matrix((np.ones(len(r)), (r, c)), shape=(nv, nv))
            ncomp, lab = connected_components(g, directed=False)
            flab = lab[t[:, 0]]
            counts = np.bincount(flab, minlength=ncomp)
            main = counts.argmax()
            mp = pos[tri[flab == main].ravel()]
            lo, hi = mp.min(0), mp.max(0); pad = (hi - lo) * PAD
            drop = np.zeros(len(tri), bool)
            tree = cKDTree(mp); gap = np.ptp(mp, 0).max() * GAP
            # Floor mats / shadow plates: any flat separate part at the feet, whatever its size.
            bh = hi[1] - lo[1]
            for ci in np.nonzero(counts > 0)[0]:
                if ci == main: continue
                cp = pos[tri[flab == ci].ravel()]
                if np.ptp(cp[:, 1]) < 0.06 * bh and cp[:, 1].max() < lo[1] + 0.06 * bh:
                    drop |= flab == ci
                    report.append(('floor', int(counts[ci])))
            for ci in np.nonzero((counts > 0) & ((counts < MAXF * len(tri)) | only_main))[0]:
                if ci == main or drop[flab == ci].any(): continue
                cp = pos[tri[flab == ci].ravel()]
                inside = np.all((cp >= lo - pad) & (cp <= hi + pad), axis=1).mean()
                dist = tree.query(cp, k=1)[0].min()
                if inside < 0.5 or dist > gap or only_main:
                    drop |= flab == ci
                    report.append((int(counts[ci]), round(float(inside), 2), round(float(dist / np.ptp(mp, 0).max()), 3)))
            if drop.any() and not dry:
                new = tri.copy(); new[drop] = tri[drop][:, :1]  # degenerate: all three = first vertex
                arr = new.astype(idx.dtype).ravel()
                b[ioff:ioff + arr.nbytes] = arr.tobytes()
                # Park the dropped vertices on a main-body vertex so bounds shrink.
                keepv = np.zeros(len(pos), bool); keepv[tri[~drop].ravel()] = True
                pv = pos.copy(); pv[~keepv] = pos[tri[~drop][0, 0]]
                poff, _ = acc_view(j, binoff, b, pr['attributes']['POSITION'])
                b[poff:poff + pv.nbytes] = pv.astype(np.float32).tobytes()
                a = j['accessors'][pr['attributes']['POSITION']]
                a['min'] = [float(x) for x in pv[keepv].min(0)]; a['max'] = [float(x) for x in pv[keepv].max(0)]
                changed_json = True
    if not dry and report:
        if changed_json:
            js = json.dumps(j, separators=(',', ':')).encode()
            js += b' ' * ((4 - len(js) % 4) % 4)
            rest = bytes(b[20 + jl:])
            b = bytearray(b[:12]) + struct.pack('<II', len(js), 0x4E4F534A) + js + rest
            b[8:12] = struct.pack('<I', len(b))
        open(p, 'wb').write(b)
    print(p.split('/')[-1], 'dropped', report)
