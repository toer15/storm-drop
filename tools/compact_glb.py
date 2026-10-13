"""Drop unreferenced accessors/bufferViews from a single-buffer GLB (used for the CC0 mirror)."""
import json, struct, sys

def _walk_acc(g):
    used = set()
    for m in g.get("meshes", []):
        for p in m.get("primitives", []):
            used.update(p.get("attributes", {}).values())
            if "indices" in p: used.add(p["indices"])
            for t in p.get("targets", []): used.update(t.values())
    for s in g.get("skins", []):
        if "inverseBindMatrices" in s: used.add(s["inverseBindMatrices"])
    for a in g.get("animations", []):
        for s in a.get("samplers", []): used.update([s["input"], s["output"]])
    return used

def compact(path, out=None):
    d = open(path, "rb").read()
    jl = struct.unpack_from("<I", d, 12)[0]
    g = json.loads(d[20:20 + jl])
    binc = d[20 + jl + 8:]
    used = sorted(_walk_acc(g))
    amap = {o: n for n, o in enumerate(used)}
    accs = [g["accessors"][i] for i in used]
    bvs = sorted({a["bufferView"] for a in accs if "bufferView" in a} |
                 {im["bufferView"] for im in g.get("images", []) if "bufferView" in im})
    bmap, newbin, newbv = {}, bytearray(), []
    for n, o in enumerate(bvs):
        bv = dict(g["bufferViews"][o]); off = bv.get("byteOffset", 0)
        while len(newbin) % 8: newbin += b"\0"
        bv["byteOffset"] = len(newbin); newbin += binc[off:off + bv["byteLength"]]
        bmap[o] = n; newbv.append(bv)
    for a in accs:
        if "bufferView" in a: a["bufferView"] = bmap[a["bufferView"]]
    for im in g.get("images", []):
        if "bufferView" in im: im["bufferView"] = bmap[im["bufferView"]]
    for m in g.get("meshes", []):
        for p in m.get("primitives", []):
            p["attributes"] = {k: amap[v] for k, v in p["attributes"].items()}
            if "indices" in p: p["indices"] = amap[p["indices"]]
            if "targets" in p: p["targets"] = [{k: amap[v] for k, v in t.items()} for t in p["targets"]]
    for s in g.get("skins", []):
        if "inverseBindMatrices" in s: s["inverseBindMatrices"] = amap[s["inverseBindMatrices"]]
    for a in g.get("animations", []):
        for s in a.get("samplers", []): s["input"] = amap[s["input"]]; s["output"] = amap[s["output"]]
    g["accessors"] = accs; g["bufferViews"] = newbv
    while len(newbin) % 4: newbin += b"\0"
    g["buffers"] = [{"byteLength": len(newbin)}]
    js = json.dumps(g, separators=(",", ":")).encode()
    while len(js) % 4: js += b" "
    total = 12 + 8 + len(js) + 8 + len(newbin)
    o = struct.pack("<III", 0x46546C67, 2, total) + struct.pack("<II", len(js), 0x4E4F534A) + js + struct.pack("<II", len(newbin), 0x004E4942) + newbin
    open(out or path, "wb").write(o)

if __name__ == "__main__":
    compact(sys.argv[1], sys.argv[2] if len(sys.argv) > 2 else None)
