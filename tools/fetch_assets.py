#!/usr/bin/env python3
"""Download the CC0 / CC-BY assets Storm Drop uses (Kenney, Quaternius, Pichuliru, Poly Haven, OpenGameArt...)
into assets/, patch the character rigs and install the import settings. Licences: CREDITS.md.
Run once after cloning:  python3 tools/fetch_assets.py   (works on Windows, macOS, Linux)."""
import base64, gzip, io, os, shutil, sys, urllib.request, zipfile
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

ROOT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "assets")
K = "https://kenney.nl/media/pages/assets/"
PACKS = {
    "nature": K + "nature-kit/37ac38a37b-1677698939/kenney_nature-kit.zip",
    "city": K + "city-kit-suburban/2c871b7af2-1745479373/kenney_city-kit-suburban_20.zip",
    "impact": K + "impact-sounds/87b4ddecda-1677589768/kenney_impact-sounds.zip",
    "ui": K + "interface-sounds/fa43c1dd4d-1677589452/kenney_interface-sounds.zip",
    "scifi": K + "sci-fi-sounds/6b296f9ecf-1677589334/kenney_sci-fi-sounds.zip",
    "jingles": K + "music-jingles/f37e530b9e-1677590399/kenney_music-jingles.zip",
    "particles": K + "particle-pack/f8fe0f8cb8-1677578741/kenney_particle-pack.zip",
    "rpg": K + "rpg-audio/8e99002d76-1677590336/kenney_rpg-audio.zip",
    "commercial": K + "city-kit-commercial/a742d900eb-1753115042/kenney_city-kit-commercial_2.1.zip",
    "industrial": K + "city-kit-industrial/0ec35b139d-1788171848/kenney_city-kit-industrial_2.0.zip",
}
G = "Models/GLB format/"
FILES = [  # (pack, path inside zip, destination under assets/)
    *[("nature", f"Models/GLTF format/{n}.glb", f"nature/{n}.glb") for n in
      ["tree_default", "tree_cone", "tree_detailed", "tree_oak", "rock_largeA", "rock_largeC", "rock_tallA", "rock_smallA"]],
    *[("city", G + f"building-type-{b}.glb", f"buildings/building-type-{b}.glb") for b in "acdefghkl"],
    ("city", G + "Textures/colormap.png", "buildings/Textures/colormap.png"),
    ("scifi", "Audio/laserSmall_000.ogg", "audio/shoot.ogg"),
    ("scifi", "Audio/forceField_000.ogg", "audio/storm.ogg"),
    ("rpg", "Audio/metalClick.ogg", "audio/reload.ogg"),
    ("impact", "Audio/impactPlank_medium_000.ogg", "audio/build.ogg"),
    ("impact", "Audio/impactGeneric_light_000.ogg", "audio/hit.ogg"),
    *[("impact", f"Audio/footstep_grass_00{i}.ogg", f"audio/footstep_grass_00{i}.ogg") for i in range(3)],
    ("ui", "Audio/click_001.ogg", "audio/click.ogg"),
    ("particles", "PNG (Transparent)/muzzle_02.png", "fx13/muzzle_front.png"),
    ("particles", "PNG (Transparent)/muzzle_01.png", "fx13/muzzle_side.png"),
    ("particles", "PNG (Transparent)/smoke_04.png", "fx13/smoke.png"),
    ("jingles", "Audio/8-Bit jingles/jingles_NES00.ogg", "audio/victory.ogg"),
    ("jingles", "Audio/Hit jingles/jingles_HIT05.ogg", "audio/eliminated.ogg"),
    # v1.4 map: Kenney City Kit (Commercial) skyscrapers/shops + low-detail LOD versions, City Kit (Industrial) (CC0)
    *[("commercial", G + f"{n}.glb", f"city14/{n}.glb") for n in
      [f"building-skyscraper-{c}" for c in "abcde"] + [f"building-{c}" for c in "abcdefgh"] + [f"low-detail-building-{c}" for c in "abcdefgh"]],
    ("commercial", G + "Textures/colormap.png", "city14/Textures/colormap.png"),
    *[("industrial", G + f"{n}.glb", f"industry14/{n}.glb") for n in
      [f"building-{c}" for c in "abcdefgh"] + ["chimney-large", "detail-tank-large", "detail-tank", "shipping-container-a",
       "shipping-container-b", "shipping-container-c", "water-tower", "windmill"]],
    ("industrial", G + "Textures/colormap.png", "industry14/Textures/colormap.png"),
]

PH = "https://dl.polyhaven.org/file/ph-assets/"
DIRECT = [  # Poly Haven (CC0): 1k textures + 1k HDRI sky, small enough for phones
    *[(PH + f"Textures/jpg/1k/{t}/{t}_{m}_1k.jpg", f"textures/{n}_{m}.jpg")
      for t, n in [("leafy_grass", "grass"), ("coast_sand_01", "sand"), ("rocky_terrain_02", "rock")] for m in ("diff", "nor_gl")],
    (PH + "HDRIs/hdr/1k/kloofendal_48d_partly_cloudy_puresky_1k.hdr", "sky/sky_1k.hdr"),
]

PP = "https://static.poly.pizza/"
# Poly Pizza direct GLBs: (uuid, destination). Licences/authors are listed in CREDITS.md.
POLY = [
    # Quaternius "Ultimate/Toon Shooter" animated characters (CC0)
    ("713f6535-f4f3-4367-a4c6-ced126ae0936", "chars13/swat.glb"),
    ("bbe369ee-a686-42c7-adad-14356f5f2f15", "chars13/adventurer.glb"),
    ("3186b8e9-afd5-4d48-846c-b2b530cd23e2", "chars13/hooded.glb"),
    ("0076345b-bbea-42d5-931c-4a5ad2050b18", "chars13/astronaut.glb"),
    ("81f2f0cf-6f53-4b57-92ea-dba0928620f2", "chars13/farmer.glb"),
    ("e56f23b5-3270-406f-8924-f77cad980c43", "chars13/punk.glb"),
    ("f771a536-1c18-4a47-bb56-ceea4b603455", "chars13/beach.glb"),
    ("90a9e2d4-053f-42f1-99a2-8f5e1180ea7f", "chars13/casual.glb"),
    ("46d6db5a-3c9f-4238-8cdf-8eb7194498dc", "chars13/woman.glb"),
    ("ba7a1955-ea51-4cb9-a561-188bdef0a6c7", "chars13/woman2.glb"),
    ("3a5f3056-ffe6-42eb-bd52-122afcbd22b2", "chars13/worker.glb"),
    # Weapons
    ("823493ed-73d8-41ae-91e4-d0b396959756", "guns13/pistol.glb"),   # Pichuliru CC0
    ("a380d523-5633-410b-88f5-558bc1a7af60", "guns13/ar.glb"),       # Pichuliru CC0
    ("b18363d2-213d-43f5-b79b-c5b2376624de", "guns13/smg.glb"),      # Pichuliru CC0
    ("f71d6771-f512-4374-bd23-ba00b564db68", "guns13/shotgun.glb"),  # Quaternius CC0
    ("f03e21b7-e3b7-49fd-b47d-d1908649fcee", "guns13/sniper.glb"),                                # Quaternius CC0
    ("613e3b1b-d07c-496b-94a1-7c85b507bac4", "guns13/rocket.glb"),   # CreativeTrio CC0
    # Pickaxes, back blings, props
    ("57c0c311-57e7-48da-8a7b-2050e8b61066", "props13/pickaxe.glb"),        # Pichuliru CC0
    ("235c512b-d2c5-4885-9502-f26ed5754891", "props13/pickaxe_diamond.glb"),                            # Quaternius CC0
    ("da91e155-332b-459d-86c2-66149fd05604", "props13/pickaxe_stone.glb"),                                # Quaternius CC0
    ("2eb5178b-0c98-4a0d-b0ea-ad8925525d1e", "props13/backpack.glb"),       # Quaternius CC0
    ("0d29cdc2-0baf-4bf7-835f-075b34c70b61", "props13/vest_pack.glb"),      # Quaternius CC0
    ("0bf6e981-5d81-446b-aeda-1908bc8d7990", "props13/chest.glb"),          # Quaternius CC0 (animated)
    ("4e925a01-dbb8-4aab-848b-221306b835ea", "props13/pickup_truck.glb"),                                # Quaternius CC0
    ("840253f1-676f-4d91-bd5c-9c6e3647ba73", "props13/stationwagon.glb"),                                 # Kay Lousberg CC0
    # v1.4 Battle Bus (both CC-BY 3.0, credit in CREDITS.md)
    ("635a02b7-4260-42a5-bd52-987511d6e3e0", "bus14/bus.glb"),          # "Bus" by Poly by Google
    ("4feb9a6e-8399-47f5-864b-b48516ec7c0f", "bus14/balloon.glb"),      # "Hot air balloon" by Poly by Google
]
OGA = "https://opengameart.org/sites/default/files/"
ZIPS = [  # (zip url, member suffix, destination)
    (OGA + "universal_animation_librarystandard.zip", "Godot/AnimationLibrary_Godot_Standard.glb", "anim13/ual1.glb"),
    (OGA + "universal_animation_library_2standard.zip", "Unreal-Godot/UAL2_Standard.glb", "anim13/ual2.glb"),
]
AUDIO = [
    (OGA + "audio_preview/awesomeness.wav.ogg", "music13/lobby.ogg"),   # "Menu Music" by mrpoly, CC0
    (OGA + "fight_looped.ogg", "music13/match.ogg"),                    # "Fast Fight/Battle Music (looped)" by XCVG, CC0
    (OGA + "22%20Pistol.wav", "sfx13/pistol.wav"),                      # "Gunshots" (OGA), CC0
    (OGA + "22%20Magnum.wav", "sfx13/heavy.wav"),
    (OGA + "Black%20Powder.wav", "sfx13/shotgun.wav"),
    (OGA + "assaultriflereload1_0.wav", "sfx13/reload_rifle.wav"),      # "Gun Reload Sounds" (OGA), CC0
    (OGA + "gunreload1.wav", "sfx13/reload_pistol.wav"),
    (OGA + "shotguncock_0.wav", "sfx13/pump.wav"),
]

def _get(url, out):
    os.makedirs(os.path.dirname(out), exist_ok=True)
    req = urllib.request.Request(url, headers={"User-Agent": "storm-drop-fetch"})
    with urllib.request.urlopen(req) as r, open(out, "wb") as o: shutil.copyfileobj(r, o)

def main():
    for url, dst in DIRECT:
        out = os.path.join(ROOT, dst)
        if os.path.exists(out): continue
        print("Downloading", url)
        os.makedirs(os.path.dirname(out), exist_ok=True)
        req = urllib.request.Request(url, headers={"User-Agent": "storm-drop-fetch"})
        with urllib.request.urlopen(req) as r, open(out, "wb") as o: shutil.copyfileobj(r, o)
    for uid, dst in POLY:
        out = os.path.join(ROOT, dst)
        if os.path.exists(out): continue
        print("Downloading", dst)
        try:
            _get(PP + uid + ".glb", out)
        except Exception as e:
            # static.poly.pizza blocks GitHub-hosted runners (HTTP 403). Fall back to the
            # in-repo CC0 mirror: the same file, unused animation data stripped, gzip+base64.
            mir = os.path.join(ROOT, "..", "tools", "mirror", dst.replace("/", "__") + ".gz.b64")
            if not os.path.exists(mir): raise
            print("  ", e, "-> using mirror", os.path.basename(mir))
            with open(mir, "rb") as f, open(out, "wb") as o: o.write(gzip.decompress(base64.b64decode(f.read())))
    for url, dst in AUDIO:
        out = os.path.join(ROOT, dst)
        if not os.path.exists(out): print("Downloading", dst); _get(url, out)
    for url, src, dst in ZIPS:
        out = os.path.join(ROOT, dst)
        if os.path.exists(out): continue
        print("Downloading", url)
        req = urllib.request.Request(url, headers={"User-Agent": "storm-drop-fetch"})
        z = zipfile.ZipFile(io.BytesIO(urllib.request.urlopen(req).read()))
        name = next(n for n in z.namelist() if n.endswith(src))
        os.makedirs(os.path.dirname(out), exist_ok=True)
        with z.open(name) as f, open(out, "wb") as o: shutil.copyfileobj(f, o)
    import fix_rig  # re-parent IK feet so the characters share the UAL animations
    for dp, _, fs in os.walk(os.path.join(ROOT, "chars13")):
        for f in fs:
            if f.endswith(".glb"): fix_rig.fix(os.path.join(dp, f))
    # Import settings (bone maps for animation retargeting) live in tools/import/
    imp = os.path.join(os.path.dirname(os.path.abspath(__file__)), "import")
    for dp, _, fs in os.walk(imp):
        for f in fs:
            rel = os.path.relpath(os.path.join(dp, f), imp)
            o = os.path.join(ROOT, rel); os.makedirs(os.path.dirname(o), exist_ok=True)
            if o.endswith(".import") and os.path.exists(o) and "bone_map" in open(o).read(): continue
            shutil.copyfile(os.path.join(dp, f), o)
    zips = {}
    for pack, src, dst in FILES:
        out = os.path.join(ROOT, dst)
        if os.path.exists(out): continue
        if pack not in zips:
            print("Downloading", PACKS[pack])
            req = urllib.request.Request(PACKS[pack], headers={"User-Agent": "storm-drop-fetch"})
            zips[pack] = zipfile.ZipFile(io.BytesIO(urllib.request.urlopen(req).read()))
        z = zips[pack]
        name = next((n for n in z.namelist() if n.endswith(src)), None)
        if name is None: sys.exit(f"missing {src} in {pack}")
        os.makedirs(os.path.dirname(out), exist_ok=True)
        with z.open(name) as f, open(out, "wb") as o: shutil.copyfileobj(f, o)
    print("Assets ready in", os.path.normpath(ROOT))

if __name__ == "__main__":
    main()
