# Storm Drop

An original, open-source battle-royale prototype made with **Godot 4** (GDScript).
Everything is built from primitive meshes and code-generated materials, so there are no external assets.

## Features
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

## How to run
1. Install [Godot 4.3+](https://godotengine.org/download) (standard version, not .NET).
2. Open Godot, click **Import**, and select `project.godot` in this folder.
3. Press **F5** (Play).

Command line: `godot --path .`

## License
MIT. See [LICENSE](LICENSE). This is a fan-made original game and is not affiliated with any other battle-royale game.
