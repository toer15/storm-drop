# Storm Drop

An original, open-source battle-royale prototype made with **Godot 4** (GDScript).
It uses free CC0 low-poly 3D models and sounds from [Kenney](https://kenney.nl) (see [CREDITS.md](CREDITS.md)); the island, storm and build pieces are generated in code.

## Features
- **Front end:** animated loading screen with key art, logo, progress bar and tips; 3D lobby with your character on a stage; tabs for Lobby, Battle Pass, Locker, Item Shop and Career; big PLAY button with Solo/Duos select (Duos is visual only) and a matchmaking countdown
- **Item Shop:** daily rotating skins, back blings, pickaxes and emotes bought with **Drop Coins**, a soft currency earned by playing (no real money). Progress is saved to `user://profile.cfg`
- **Locker:** equip owned cosmetics; they show in the lobby and in the match
- **Battle Pass:** 20 tiers unlocked with match XP (eliminations, placement, wins)
- **Career:** matches, wins, win rate, eliminations, K/D, top 10s, best placement, time played
- **Match:** Storm Bus drop + glider, loot chests, floor loot with 5 weapon types (Pistol, Assault Rifle, SMG, Shotgun, Sniper) in 5 rarity colours, pickaxe to harvest materials, 4-slot hotbar, emotes, victory screen with XP/coin rewards
- Animated low-poly characters (idle, walk, sprint, jump, shoot, death), a blaster model, trees, rocks and houses from Kenney (CC0)
- Sound effects: gunshots, reload, building, footsteps, hit markers, storm hum, UI clicks, victory/elimination jingles
- Loading screen with title, progress bar, and rotating tips (async `ResourceLoader.load_threaded_request`)
- Main menu (Play / Settings / Quit) over a rotating 3D lobby background
- Settings: mouse sensitivity, bot count, fullscreen
- Third-person character controller (WASD, jump, sprint, mouse look)
- Hitscan rifle with ammo, reserve ammo, and reload
- Grid-snapped building: walls, floors, ramps (pieces can be shot down)
- Procedurally generated island: noise terrain, beach, trees, rocks, houses
- Shrinking storm circle that moves, with damage that increases each phase
- AI bots that roam toward the safe zone, chase, strafe, and shoot
- HUD: health, shield, ammo, materials/build mode, players left, storm timer, minimap, kill feed
- Victory and elimination screens with Play Again / Back to Menu

## Controls
| Key | Action |
|---|---|
| WASD | Move |
| Mouse | Look |
| Shift | Sprint |
| Space | Jump |
| Left click | Shoot, or place a piece in build mode |
| R | Reload |
| Z / X / C (or Q) | Build wall / floor / ramp (press again to exit) |
| 1 | Back to weapon |
| 1-4 | Pickaxe / weapon slots |
| E | Open chest / swap weapon |
| B | Emote |
| Space (on the bus) | Drop, then steer the glider with WASD |
| Esc | Release the mouse |

## Play on your phone
- **Browser:** open **https://toer15.github.io/storm-drop/** in Chrome (Android) or Safari (iOS), turn your phone sideways, and tap to start. "Add to Home Screen" installs it like an app (PWA).
- **Android APK:** in Godot, install the Android export templates and an Android SDK/debug keystore (Editor Settings > Export > Android), then **Project > Export > Android > Export Project**.

### Touch controls
Shown automatically on touchscreens; toggle them in **Settings > Touch controls**.
| Control | Action |
|---|---|
| Left side drag (virtual joystick) | Move |
| Right side drag | Look |
| FIRE | Shoot (hold), or place a piece in build mode |
| JUMP / SPRINT (hold) | Jump / sprint |
| RELOAD | Reload |
| WALL / FLOOR / RAMP | Build modes |
| SWAP | Cycle pickaxe / weapons |
| USE | Open chest / swap weapon |
| EMOTE | Emote |
| II (top centre) | Leave the match |

The UI scales to any screen size (stretch mode `canvas_items`, aspect `expand`), the game is locked to landscape, and it uses the Compatibility (OpenGL ES 3 / WebGL 2) renderer so it runs on phones and in browsers. The web export has threads disabled, so it needs no special server headers.

## Web build / GitHub Pages
Each push to `main` runs `.github/workflows/web.yml`, which exports the Web build and publishes it to the `gh-pages` branch. To build it yourself: `godot --headless --export-release "Web" build/web/index.html`, then serve `build/web` over HTTP.

## How to run
0. **Fetch the art and sound (one time):** `python3 tools/fetch_assets.py` downloads the CC0 Kenney packs and copies the needed files into `assets/` (they aren't stored in git).
1. Install [Godot 4.3+](https://godotengine.org/download) (standard version, not .NET).
2. Open Godot, click **Import**, and select `project.godot` in this folder.
3. Press **F5** (Play).

Command line: `godot --path .`

## Downloads
Prebuilt Windows, Linux, Web and Android (APK) builds are on the [Releases page](https://github.com/toer15/storm-drop/releases).

## License
MIT. See [LICENSE](LICENSE). This is a fan-made original game and is not affiliated with any other battle-royale game.

## v1.2.0 — Visual overhaul & human-like AI
- **Look:** PBR terrain blend (grass/sand/rock by height & slope, Poly Haven CC0 textures), HDRI sky, soft-shadow sun, SSAO/glow/fog on desktop (lighter on mobile/web), rim light + ink outline, wavy fresnel water with shore foam, wind-swayed foliage, more house types, randomised bot outfits.
- **Bots ride the Battle Bus** and glide to their own drop spots.
- **Utility AI:** every ~0.3 s each bot scores Roam, Loot weapon, Open chest, Rotate, Engage, Third-party, Retreat, Heal, Build cover and Camp, with hysteresis. Personalities: Aggressive, Cautious, Looter, Builder.
- **Movement:** runtime-baked NavigationRegion3D + NavigationAgent3D, acceleration/turning, strafing, jump spam, crouch peeks, reaction time & aim error by skill, spray vs tap fire, builds walls/ramps when shot.
- **Difficulty** (Easy/Normal/Hard) in Settings. **AI debug overlay:** Settings checkbox or **F3** in match shows each bot's persona and current decision.
- Mobile performance: staggered thinking (slower for far bots), lighter post-processing.

## v1.3.0 — Real characters, guns, animations & music
- **11 Quaternius outfits** (SWAT, Adventurer, Astronaut, Punk, ...) replace the blocky minis, all driven by one shared **Universal Animation Library** set (CC0) retargeted at import: idle, jog, sprint, crouch, crouch-walk, jump/fall/land, glide, sit (bus), aim, shoot, reload, pickaxe swing, build/interact, chest open, heal, hit, death.
- **12 emotes** including Groove (dance), Zombie Shuffle, Hocus Pocus, Dry Swim, Floor Slide, Wave, Shadow Box, Unbothered, On The Phone.
- **Realistic stylised guns** (Pichuliru / Quaternius / CreativeTrio, CC0): pistol, assault rifle, SMG, pump shotgun, sniper and the new **rocket launcher** (splash damage, explosion). Muzzle flashes, recoil, reload animation and real gunshot/reload sounds.
- **First-person view**: press **V** (or the VIEW touch button) for a first-person camera with a view-model gun.
- **Real pickaxe and backpack models**, animated **treasure chests** that open, **parked cars**.
- **Music**: lobby and match loops (CC0, OpenGameArt).
- Mobile: outlines are skipped and muzzle lights disabled on phones/web; animations are shared resources (loaded once).
- All sources, authors, licences and URLs: see CREDITS.md.
