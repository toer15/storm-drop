# Credits

All third-party assets are **CC0 1.0 (public domain)** by **Kenney** (https://www.kenney.nl). Credit isn't required, but it's given here with thanks.

| Asset pack | Used for | Source |
|---|---|---|
| Mini Characters 1.0 | All 12 outfits for the player and bots (idle/walk/sprint/jump/fall/shoot/die animations) | https://kenney.nl/assets/mini-characters |
| Blaster Kit 2.1 | Weapon models (`blaster-a/b/c/d/h` for AR/Pistol/SMG/Shotgun/Sniper) | https://kenney.nl/assets/blaster-kit |
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
- Background music: none yet. Only short CC0 jingles from Kenney Music Jingles are used

## Sources checked
Quaternius (Ultimate Animated Character Pack, Animated Men; CC0), Poly Pizza, OpenGameArt, itch.io CC0 and Sketchfab CC0/CC-BY were checked as well. Kenney's Mini Characters were picked because they ship as GLB with a full matching set of animations (idle, walk, sprint, jump, fall, holding/shooting, melee, die and emotes) on one rig, are tiny (~250 KB each, good for phones) and are CC0, so they are fine to redistribute.

The assets are downloaded by `tools/fetch_assets.py` rather than stored in git.

## Added in v1.2.0
- **Poly Haven** (https://polyhaven.com) — CC0: textures `leafy_grass`, `coast_sand_01`, `rocky_terrain_02`; HDRI `kloofendal_48d_partly_cloudy_puresky` (Greg Zaal / Poly Haven). Downloaded by `tools/fetch_assets.py`.
- Sources checked but not used: Quaternius, Poly Pizza, Sketchfab CC0/CC-BY, ambientCG (Kenney + Poly Haven already covered the needs in one consistent style).
- Procedural (made in this project): terrain blend, water, outline/rim shaders, storm wall, bus/glider, chests, build pieces, island height map.
