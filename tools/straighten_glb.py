"""Straighten a leaning GLB: shear z by -k*(y - ymin) (k = fitted slope of the
body's z-centroid over height), fixing NORMAL/TANGENT and the POSITION bounds.
usage: shear_fix.py in.glb out.glb [k]"""
import sys, struct, json, numpy as np
src, dst = sys.argv[1], sys.argv[2]
b = bytearray(open(src, 'rb').read()); jl = struct.unpack('<I', b[12:16])[0]; j = json.loads(b[20:20 + jl]); bo = 20 + jl + 8
def view(ai, n):
    a = j['accessors'][ai]; bv = j['bufferViews'][a['bufferView']]
    assert bv.get('byteStride', 0) in (0, 4 * n)
    off = bo + bv.get('byteOffset', 0) + a.get('byteOffset', 0)
    return off, np.frombuffer(b, np.float32, a['count'] * n, off).reshape(-1, n).copy()
for m in j['meshes']:
    for pr in m['primitives']:
        at = pr['attributes']
        off, pos = view(at['POSITION'], 3)
        y = pos[:, 1]; ys = np.linspace(y.min(), y.max(), 21)
        cz = [pos[(y >= ys[i]) & (y < ys[i + 1]), 2].mean() for i in range(20)]
        k = float(sys.argv[3]) if len(sys.argv) > 3 else np.polyfit(ys[:-1], cz, 1)[0]
        M = np.eye(3); M[2, 1] = -k             # z' = z - k*y
        pos = pos @ M.T; pos[:, 2] += k * y.min()
        pos[:, 2] -= (pos[:, 2].min() + pos[:, 2].max()) / 2 - 0  # keep it centred
        pos = pos.astype(np.float32); b[off:off + pos.nbytes] = pos.tobytes()
        a = j['accessors'][at['POSITION']]; a['min'] = pos.min(0).tolist(); a['max'] = pos.max(0).tolist()
        N = np.linalg.inv(M).T
        if 'NORMAL' in at:
            off, n = view(at['NORMAL'], 3); n = n @ N.T; n /= np.linalg.norm(n, axis=1, keepdims=True) + 1e-12
            n = n.astype(np.float32); b[off:off + n.nbytes] = n.tobytes()
        if 'TANGENT' in at:
            off, t = view(at['TANGENT'], 4); t3 = t[:, :3] @ M.T; t3 /= np.linalg.norm(t3, axis=1, keepdims=True) + 1e-12
            t[:, :3] = t3; t = t.astype(np.float32); b[off:off + t.nbytes] = t.tobytes()
        print('sheared k=%.3f' % k)
js = json.dumps(j, separators=(',', ':')).encode(); js += b' ' * ((4 - len(js) % 4) % 4)
out = bytearray(b[:12]) + struct.pack('<II', len(js), 0x4E4F534A) + js + bytes(b[20 + jl:])
out[8:12] = struct.pack('<I', len(out)); open(dst, 'wb').write(out)
