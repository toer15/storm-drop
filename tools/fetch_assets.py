#!/usr/bin/env python3
"""Download the CC0 Kenney asset packs Storm Drop uses and copy the needed files into assets/.
Run once after cloning:  python3 tools/fetch_assets.py   (works on Windows, macOS, Linux)."""
import io, os, shutil, sys, urllib.request, zipfile

ROOT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "assets")
K = "https://kenney.nl/media/pages/assets/"
PACKS = {
    "chars": K + "mini-characters/bfc7e272b4-1774770718/kenney_mini-characters.zip",
    "blaster": K + "blaster-kit/261d80a716-1753959510/kenney_blaster-kit_2.1.zip",
    "nature": K + "nature-kit/37ac38a37b-1677698939/kenney_nature-kit.zip",
    "city": K + "city-kit-suburban/2c871b7af2-1745479373/kenney_city-kit-suburban_20.zip",
    "impact": K + "impact-sounds/87b4ddecda-1677589768/kenney_impact-sounds.zip",
    "ui": K + "interface-sounds/fa43c1dd4d-1677589452/kenney_interface-sounds.zip",
    "scifi": K + "sci-fi-sounds/6b296f9ecf-1677589334/kenney_sci-fi-sounds.zip",
    "jingles": K + "music-jingles/f37e530b9e-1677590399/kenney_music-jingles.zip",
    "rpg": K + "rpg-audio/8e99002d76-1677590336/kenney_rpg-audio.zip",
}
G = "Models/GLB format/"
FILES = [  # (pack, path inside zip, destination under assets/)
    *[("chars", G + f"character-{c}.glb", f"characters/character-{c}.glb") for c in ["male-a", "male-c", "female-b", "female-d"]],
    ("chars", G + "Textures/colormap.png", "characters/Textures/colormap.png"),
    ("blaster", G + "blaster-a.glb", "weapons/blaster-a.glb"),
    ("blaster", G + "Textures/colormap.png", "weapons/Textures/colormap.png"),
    *[("nature", f"Models/GLTF format/{n}.glb", f"nature/{n}.glb") for n in
      ["tree_default", "tree_cone", "tree_detailed", "tree_oak", "rock_largeA", "rock_largeC", "rock_tallA", "rock_smallA"]],
    *[("city", G + f"building-type-{b}.glb", f"buildings/building-type-{b}.glb") for b in "acfk"],
    ("city", G + "Textures/colormap.png", "buildings/Textures/colormap.png"),
    ("scifi", "Audio/laserSmall_000.ogg", "audio/shoot.ogg"),
    ("scifi", "Audio/forceField_000.ogg", "audio/storm.ogg"),
    ("rpg", "Audio/metalClick.ogg", "audio/reload.ogg"),
    ("impact", "Audio/impactPlank_medium_000.ogg", "audio/build.ogg"),
    ("impact", "Audio/impactGeneric_light_000.ogg", "audio/hit.ogg"),
    *[("impact", f"Audio/footstep_grass_00{i}.ogg", f"audio/footstep_grass_00{i}.ogg") for i in range(3)],
    ("ui", "Audio/click_001.ogg", "audio/click.ogg"),
    ("jingles", "Audio/8-Bit jingles/jingles_NES00.ogg", "audio/victory.ogg"),
    ("jingles", "Audio/Hit jingles/jingles_HIT05.ogg", "audio/eliminated.ogg"),
]

def main():
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
