"""Patch Quaternius shooter-character GLBs so they retarget cleanly onto the Universal Animation Library:
their feet are IK-style bones parented to Root, so we re-parent Foot.L/R under LowerLeg.L/R (keeping the
same global rest pose; inverse bind matrices are global so skinning is unchanged) and drop the baked
native clips (they animate feet in Root space). Pure Python, no numpy needed."""
import json, struct, math

def q2m(q):
    x, y, z, w = q
    return [[1-2*(y*y+z*z), 2*(x*y-z*w), 2*(x*z+y*w)], [2*(x*y+z*w), 1-2*(x*x+z*z), 2*(y*z-x*w)], [2*(x*z-y*w), 2*(y*z+x*w), 1-2*(x*x+y*y)]]

def trs(n):
    if "matrix" in n:
        m = n["matrix"]; return [[m[c*4+r] for c in range(4)] for r in range(4)]
    t = n.get("translation", [0, 0, 0]); r = q2m(n.get("rotation", [0, 0, 0, 1])); s = n.get("scale", [1, 1, 1])
    return [[r[i][0]*s[0], r[i][1]*s[1], r[i][2]*s[2], t[i]] for i in range(3)] + [[0, 0, 0, 1]]

def mul(a, b): return [[sum(a[i][k]*b[k][j] for k in range(4)) for j in range(4)] for i in range(4)]

def inv(m):  # affine inverse (rotation*scale + translation)
    a = [r[:3] for r in m[:3]]
    det = (a[0][0]*(a[1][1]*a[2][2]-a[1][2]*a[2][1]) - a[0][1]*(a[1][0]*a[2][2]-a[1][2]*a[2][0]) + a[0][2]*(a[1][0]*a[2][1]-a[1][1]*a[2][0]))
    c = [[(a[(j+1)%3][(i+1)%3]*a[(j+2)%3][(i+2)%3] - a[(j+1)%3][(i+2)%3]*a[(j+2)%3][(i+1)%3])/det for j in range(3)] for i in range(3)]
    t = [-sum(c[i][k]*m[k][3] for k in range(3)) for i in range(3)]
    return [c[i] + [t[i]] for i in range(3)] + [[0, 0, 0, 1]]

def m2trs(m):
    s = [math.sqrt(sum(m[r][c]**2 for r in range(3))) for c in range(3)]
    r = [[m[i][c]/s[c] for c in range(3)] for i in range(3)]
    tr = r[0][0]+r[1][1]+r[2][2]
    if tr > 0:
        w = math.sqrt(1+tr)*2; q = [(r[2][1]-r[1][2])/w, (r[0][2]-r[2][0])/w, (r[1][0]-r[0][1])/w, w/4]
    elif r[0][0] > r[1][1] and r[0][0] > r[2][2]:
        w = math.sqrt(1+r[0][0]-r[1][1]-r[2][2])*2; q = [w/4, (r[0][1]+r[1][0])/w, (r[0][2]+r[2][0])/w, (r[2][1]-r[1][2])/w]
    elif r[1][1] > r[2][2]:
        w = math.sqrt(1+r[1][1]-r[0][0]-r[2][2])*2; q = [(r[0][1]+r[1][0])/w, w/4, (r[1][2]+r[2][1])/w, (r[0][2]-r[2][0])/w]
    else:
        w = math.sqrt(1+r[2][2]-r[0][0]-r[1][1])*2; q = [(r[0][2]+r[2][0])/w, (r[1][2]+r[2][1])/w, w/4, (r[1][0]-r[0][1])/w]
    return [m[0][3], m[1][3], m[2][3]], q, s

def fix(path):
    b = open(path, "rb").read()
    jl = struct.unpack("<I", b[12:16])[0]; j = json.loads(b[20:20+jl]); rest = b[20+jl:]
    if j.get("extras", {}).get("storm_drop_fixed"): return False
    N = j["nodes"]; par = {}
    for i, n in enumerate(N):
        for c in n.get("children", []): par[c] = i
    name = {n.get("name"): i for i, n in enumerate(N)}
    def glob(i):
        m = trs(N[i])
        while i in par: i = par[i]; m = mul(trs(N[i]), m)
        return m
    for s in ("L", "R"):
        f, p = name.get("Foot." + s), name.get("LowerLeg." + s)
        if f is None or p is None or par.get(f) == p: continue
        local = mul(inv(glob(p)), glob(f))
        N[par[f]]["children"].remove(f); N[p].setdefault("children", []).append(f); par[f] = p
        t, q, sc = m2trs(local)
        for k in ("matrix",): N[f].pop(k, None)
        N[f]["translation"], N[f]["rotation"], N[f]["scale"] = t, q, sc
    j.pop("animations", None)
    j.setdefault("extras", {})["storm_drop_fixed"] = True
    js = json.dumps(j, separators=(",", ":")).encode()
    js += b" " * ((4 - len(js) % 4) % 4)
    out = b[:12] + struct.pack("<I", len(js)) + b"JSON" + js + rest
    out = out[:8] + struct.pack("<I", len(out)) + out[12:]
    open(path, "wb").write(out)
    return True
