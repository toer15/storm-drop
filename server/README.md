# Storm Drop dedicated server

There is **no public matchmaking server** for Storm Drop. You play online by hosting from the game
(**ONLINE > HOST GAME**) or by running this headless dedicated server yourself.

| What | How |
|---|---|
| Linux, no Docker | `./run_server.sh` (ENet/UDP) or `./run_server.sh --ws` (WebSocket) |
| Docker | `docker build -t storm-drop-server .` then `docker run -d -p 7777:7777/udp -p 7777:7777/tcp storm-drop-server` |
| Docker, WebSocket | `docker run -d -p 7777:7777/tcp -e PROTO=--ws storm-drop-server` |
| fly.io | install `flyctl`, edit `app` in `fly.toml`, then `fly launch --no-deploy --copy-config` and `fly deploy` |

Options (env vars for Docker / `run_server.sh`, or command-line args after `--`):
`--port=7777` (`PORT`), `--bots=30` (`BOTS`, max 51 minus players), `--max=16` (`MAXP`), `--ws` (`PROTO=--ws`).

Players join with **ONLINE > Server address**:
* ENet server: the server's IP (e.g. `203.0.113.7`) and port `7777`, protocol **ENet**. Open/forward **UDP 7777**.
* WebSocket server: `ws://203.0.113.7:7777` (protocol **WebSocket**). Browsers on https pages (GitHub Pages) need
  `wss://`, which fly.io gives you for free: use `wss://<your-app>.fly.dev`.

The match starts 10 seconds after everyone in the lobby presses **READY**; players go back to the lobby after each match.

Costs: fly.io is pay-as-you-go (a shared-cpu-1x / 1 GB machine is a few US dollars a month; new accounts get trial credit,
UDP/ENet on fly needs a dedicated IPv4 which is extra, so use the WebSocket mode there). A free option is an
always-free cloud VM (e.g. Oracle Cloud Free Tier) running the Docker image or `run_server.sh`.
