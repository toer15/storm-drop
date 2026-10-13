# Credits

All third-party assets are **CC0 1.0 (public domain)** unless marked otherwise. Credit isn't required for CC0, but it's given here with thanks. As of v1.3.0 characters, guns, pickaxes, back packs, chests, cars, animations, music and gun sounds come from the sources in the **v1.3.0** section below; the Kenney packs listed first are still used for nature, houses and UI/impact sounds.

| Asset pack | Used for | Source |
|---|---|---|
| Mini Characters 1.0 / Blaster Kit 2.1 | Characters and guns up to v1.2 (replaced in v1.3, no longer downloaded) | https://kenney.nl/assets/mini-characters, https://kenney.nl/assets/blaster-kit |
| Particle Pack | Muzzle-flash sprites (`muzzle_01/02`) and rocket smoke (`smoke_04`), v1.3 | https://kenney.nl/assets/particle-pack |
| Nature Kit | Trees and rocks | https://kenney.nl/assets/nature-kit |
| City Kit (Suburban) 2.0 | Houses | https://kenney.nl/assets/city-kit-suburban |
| Sci-fi Sounds | Gunshot (`laserSmall_000`), storm hum (`forceField_000`) | https://kenney.nl/assets/sci-fi-sounds |
| Impact Sounds | Footsteps (grass), build (`impactPlank_medium`), hit marker | https://kenney.nl/assets/impact-sounds |
| RPG Audio | Reload (`metalClick`) | https://kenney.nl/assets/rpg-audio |
| Interface Sounds | UI click | https://kenney.nl/assets/interface-sounds |
| Music Jingles | Victory and elimination jingles | https://kenney.nl/assets/music-jingles |

License: https://creativecommons.org/publicdomain/zero/1.0/

Game code: MIT, see LICENSE.

## Procedural / code-made content
These were made in code because no suitable redistributable asset fit (or a code version was simpler for mobile):
- Island terrain (noise heightmap), water, storm wall, Storm Bus and balloon, glider, build pieces (walls/floors/ramps), loot chests, back blings and pickaxe heads (primitive meshes)
- Loading-screen key art (storm swirl, lightning, skyline and gliders drawn with Godot 2D draw calls), lobby stage and crystals

## Sources checked
Quaternius (Ultimate Animated Character Pack, Animated Men; CC0), Poly Pizza, OpenGameArt, itch.io CC0 and Sketchfab CC0/CC-BY were checked as well. Kenney's Mini Characters were picked because they ship as GLB with a full matching set of animations (idle, walk, sprint, jump, fall, holding/shooting, melee, die and emotes) on one rig, are tiny (~250 KB each, good for phones) and are CC0, so they are fine to redistribute.

The assets are downloaded by `tools/fetch_assets.py` rather than stored in git.

## Added in v1.2.0
- **Poly Haven** (https://polyhaven.com) — CC0: textures `leafy_grass`, `coast_sand_01`, `rocky_terrain_02`; HDRI `kloofendal_48d_partly_cloudy_puresky` (Greg Zaal / Poly Haven). Downloaded by `tools/fetch_assets.py`.
- Sources checked but not used: Quaternius, Poly Pizza, Sketchfab CC0/CC-BY, ambientCG (Kenney + Poly Haven already covered the needs in one consistent style).
- Procedural (made in this project): terrain blend, water, outline/rim shaders, storm wall, bus/glider, chests, build pieces, island height map.

## Added in v1.3.0 (characters, animations, guns, props, music)
Every file below is downloaded by `tools/fetch_assets.py` from the URL given. Poly Pizza model pages state the licence; all picked models are **CC0 1.0**.

| Asset | Author | Licence | Used for | URL |
|---|---|---|---|---|
| SWAT, Adventurer, Hooded Adventurer, Astronaut, Farmer, Punk, Beach Character, Casual Character, Animated Woman (x2), Worker | Quaternius | CC0 | The 11 outfit models (player + bots) | https://poly.pizza/m/Btfn3G5Xv4 · /m/5EGWBMpuXq · /m/y9KWOVG21R · /m/3hC2i0CTuO · /m/7pn3R6hPvE · /m/BTALZymknF · /m/DojKLcO34E · /m/kZ3DmIoGip · /m/nIItLV9nxS · /m/qJ2gsTUBHL · /m/Yg2bQZO6Hj |
| Universal Animation Library (Standard) | Quaternius | CC0 | Idle, jog, sprint, walk, crouch idle/walk, jump start/loop/land (fall), death, hit, roll, pistol aim/shoot/reload, interact (build), sitting (bus), dance, spell, swim, punch emotes | https://opengameart.org/content/universal-animation-library |
| Universal Animation Library 2 (Standard) | Quaternius | CC0 | Pickaxe swing (TreeChopping), chest open, consume (heal), glide pose (NinjaJump idle), Yes / No / Fold arms / Phone / Zombie / Slide / Rail-call (wave) emotes | https://opengameart.org/content/universal-animation-library-2 |
| Pistol West | Pichuliru | CC0 | Pistol | https://poly.pizza/m/r8RjoAwN5A |
| Assault Rifle West | Pichuliru | CC0 | Assault rifle | https://poly.pizza/m/ss1nz3gJnx |
| Smg West | Pichuliru | CC0 | SMG | https://poly.pizza/m/7Dh5JSbZcp |
| Shotgun | Quaternius | CC0 | Pump shotgun | https://poly.pizza/m/ZmPTnh7njL |
| Sniper Rifle | Quaternius | CC0 | Sniper | https://poly.pizza/m/ASOMZIErq3 |
| Bazooka | CreativeTrio | CC0 | Rocket launcher (new weapon) | https://poly.pizza/m/eJNzLpBsEt |
| Pickaxe | Pichuliru | CC0 | Default pickaxe ("Trusty Axe", tinted for "Void Cleaver") | https://poly.pizza/m/u4HkEYF35S |
| Diamond Pickaxe / Stone Pickaxe | Quaternius | CC0 | Neon / Gold / Candy / Void pickaxes (tinted) | https://poly.pizza/m/2M0LyYml6j · https://poly.pizza/m/pvOeJ5EcpW |
| Backpack / Backpack (vest) | Quaternius | CC0 | "Cube Pack", "Candy Pack", "Jet Tank" back blings | https://poly.pizza/m/vF7TuXCPDH · https://poly.pizza/m/2g9Jm7kvIU |
| Chest (animated) | Quaternius | CC0 | Loot chests, plays its own Chest_Open animation | https://poly.pizza/m/eEcIqgJzJ1 |
| Pickup Truck | Quaternius | CC0 | Parked cars | https://poly.pizza/m/qn4grQgHm8 |
| Stationwagon | Kay Lousberg | CC0 | Parked cars | https://poly.pizza/m/vTTTjDoxhV |
| Menu Music | mrpoly | CC0 | Lobby music (loop) | https://opengameart.org/content/menu-music |
| Fast Fight/Battle Music (looped) | XCVG | CC0 | In-match music (loop) | https://opengameart.org/content/fast-fight-battle-music-looped |
| Gunshots (`22 Pistol`, `22 Magnum`, `Black Powder`) | kurt | CC0 | Pistol/SMG, AR, shotgun/sniper/rocket shots | https://opengameart.org/content/gunshots |
| Gun Reload Sounds | SpringySpringo | CC0 | Rifle/pistol reload, shotgun pump | https://opengameart.org/content/gun-reload-sounds |

How the animations fit every character: `tools/fix_rig.py` re-parents the Quaternius IK-style foot bones under the shins (same rest pose, no skinning change), then Godot's importer retargets both the characters and the two animation libraries onto its humanoid `SkeletonProfile` (bone maps in `tools/import/rig/`), so one animation set drives all 11 outfits.

### v1.3.0 procedural / code-made
- Gun recoil, reload dip and pickaxe swing for the first-person view model (code-driven, the gun models have no animations)
- Rocket explosion fireball (sphere) — the smoke is the Kenney particle sprite
- Glowing "Storm Orb" and "Gold Crystal" back blings (primitive shapes, kept on purpose as magic items)

### v1.3.0 sources searched
Quaternius (site, itch.io, Poly Pizza, OpenGameArt), Poly Pizza, OpenGameArt, itch.io free CC0/CC-BY packs, Sketchfab downloadable CC0/CC-BY, Poly Haven models, Kenney, GitHub CC0 mirrors (e.g. J-Ponzo/gltf-universal-animation-library), Mixamo alternatives (Quaternius UAL, Cinevva UAL retarget tool) and Freesound/OpenGameArt for audio. Not used and why:
- Quaternius *Universal Base Characters* and *Ultimate/Animated Guns* (CC0): only offered through itch.io's download page, which can't be fetched reliably by the build script; the Poly Pizza / OpenGameArt mirrors of the same author were used instead. Quaternius' *Animated Pistol* is CC-BY on Poly Pizza and its reload/fire clips only cover the pistol, so the guns use code recoil for consistency.
- Sketchfab CC-BY guns/characters: download requires a logged-in API token, which a public CI build can't use.
- Mixamo: its licence does not allow redistributing the animation files in a public repo.
- Freesound: most good gun sounds are CC-BY-NC or need an account to download; the OpenGameArt CC0 sets were used.

### CC0 mirror (tools/mirror)
static.poly.pizza blocks GitHub-hosted CI runners (HTTP 403), so `tools/mirror/` keeps gzip+base64 copies of the Poly Pizza
models listed above (all CC0, same authors/URLs as in the table). The only change is that unused animation data was stripped
(`tools/fix_rig.py` + `tools/compact_glb.py`). `tools/fetch_assets.py` downloads from Poly Pizza first and uses the mirror only if that fails.

## v1.4.0 additions
- **Kenney – City Kit (Commercial) 2.1** (CC0) – skyscrapers, shops and low-detail LOD buildings for Storm City. https://kenney.nl/assets/city-kit-commercial
- **Kenney – City Kit (Industrial) 2.0** (CC0) – Rust Works factory, Port Gale containers, water tower, windmill. https://kenney.nl/assets/city-kit-industrial
- **"Bus" by Poly by Google** – **CC-BY 3.0** – Battle Bus. https://poly.pizza/m/4CPpvEmrMoF
- **"Hot air balloon" by Poly by Google** – **CC-BY 3.0** – balloon that carries the bus. https://poly.pizza/m/8azSIUgP0ow
- Searched for a CC0 bus or balloon on Poly Pizza, Kenney, Quaternius, OpenGameArt and Sketchfab and found none good enough, so these two use CC-BY (attribution above).
