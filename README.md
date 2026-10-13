# Storm Drop

An original, open-source battle-royale prototype made with **Godot 4** (GDScript).
It uses free CC0 low-poly 3D models and sounds from [Kenney](https://kenney.nl) (see [CREDITS.md](CREDITS.md)); the island, storm and build pieces are generated in code.

## Features
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
| WALL / FLOOR / RAMP / GUN | Build modes / back to weapon |
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
