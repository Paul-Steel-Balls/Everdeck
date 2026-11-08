"""Shrink the generated 3D models for shipping.

  * base color -> 512px JPEG, normal map -> 512px JPEG, occlusion/rough/metal
    -> 256px JPEG (one shared image in these models)
  * drop TANGENT (Godot rebuilds tangents on load)
  * 16-bit indices when the vertex count allows
usage: optimize_glb.py in.glb out.glb
"""
import io, json, struct, sys
import numpy as np
from PIL import Image

SIZES = {"base": (512, 85), "normal": (512, 90), "orm": (256, 85)}


def read(path):
    b = open(path, "rb").read()
    jl = struct.unpack("<I", b[12:16])[0]
    j = json.loads(b[20:20 + jl])
    bl = struct.unpack("<I", b[20 + jl:24 + jl])[0]
    return j, b[28 + jl:28 + jl + bl]


def main(src, dst):
    j, binb = read(src)
    views = [binb[v.get("byteOffset", 0):v.get("byteOffset", 0) + v["byteLength"]] for v in j["bufferViews"]]
    role = {}
    for m in j.get("materials", []):
        pbr = m.get("pbrMetallicRoughness", {})
        for key, r in (("baseColorTexture", "base"), ("metallicRoughnessTexture", "orm")):
            if key in pbr:
                role[j["textures"][pbr[key]["index"]]["source"]] = r
        if "normalTexture" in m:
            role[j["textures"][m["normalTexture"]["index"]]["source"]] = "normal"
        if "occlusionTexture" in m:
            role.setdefault(j["textures"][m["occlusionTexture"]["index"]]["source"], "orm")
    for ii, img in enumerate(j.get("images", [])):
        size, q = SIZES[role.get(ii, "base")]
        im = Image.open(io.BytesIO(views[img["bufferView"]])).convert("RGB")
        if max(im.size) > size:
            im = im.resize((size, size), Image.LANCZOS)
        out = io.BytesIO()
        im.save(out, "JPEG", quality=q, optimize=True)
        views[img["bufferView"]] = out.getvalue()
        img["mimeType"] = "image/jpeg"
    drop = set()
    drop_acc = set()
    for m in j["meshes"]:
        for pr in m["primitives"]:
            if "TANGENT" in pr["attributes"]:
                ai = pr["attributes"].pop("TANGENT")
                drop_acc.add(ai)
                drop.add(j["accessors"][ai]["bufferView"])
            ia = j["accessors"][pr["indices"]]
            if ia["componentType"] == 5125:
                nverts = j["accessors"][pr["attributes"]["POSITION"]]["count"]
                if nverts < 65535:
                    a = np.frombuffer(views[ia["bufferView"]], np.uint32, ia["count"], ia.get("byteOffset", 0))
                    views[ia["bufferView"]] = a.astype(np.uint16).tobytes()
                    ia["componentType"] = 5123
                    ia["byteOffset"] = 0
    # Repack the binary chunk (dropped views become empty, then removed).
    keep = [i for i in range(len(views)) if i not in drop]
    remap = {old: new for new, old in enumerate(keep)}
    newviews, blob = [], bytearray()
    for old in keep:
        v = dict(j["bufferViews"][old])
        data = views[old]
        while len(blob) % 4:
            blob += b"\0"
        v["byteOffset"] = len(blob)
        v["byteLength"] = len(data)
        blob += data
        newviews.append(v)
    for a in j["accessors"]:
        if a.get("bufferView") in remap:
            a["bufferView"] = remap[a["bufferView"]]
    # Remove the dropped accessors and renumber every reference to the rest.
    akeep = [i for i in range(len(j["accessors"])) if i not in drop_acc]
    amap = {old: new for new, old in enumerate(akeep)}
    j["accessors"] = [j["accessors"][i] for i in akeep]
    for m in j["meshes"]:
        for pr in m["primitives"]:
            pr["attributes"] = {k: amap[v] for k, v in pr["attributes"].items()}
            if "indices" in pr:
                pr["indices"] = amap[pr["indices"]]
    for sk in j.get("skins", []):
        if "inverseBindMatrices" in sk:
            sk["inverseBindMatrices"] = amap[sk["inverseBindMatrices"]]
    for an in j.get("animations", []):
        for smp in an["samplers"]:
            smp["input"] = amap[smp["input"]]
            smp["output"] = amap[smp["output"]]
    for img in j.get("images", []):
        img["bufferView"] = remap[img["bufferView"]]
    j["bufferViews"] = newviews
    while len(blob) % 4:
        blob += b"\0"
    j["buffers"] = [{"byteLength": len(blob)}]
    js = json.dumps(j, separators=(",", ":")).encode()
    js += b" " * ((4 - len(js) % 4) % 4)
    out = struct.pack("<III", 0x46546C67, 2, 12 + 8 + len(js) + 8 + len(blob))
    out += struct.pack("<II", len(js), 0x4E4F534A) + js + struct.pack("<II", len(blob), 0x004E4942) + blob
    open(dst, "wb").write(out)


if __name__ == "__main__":
    main(sys.argv[1], sys.argv[2])
