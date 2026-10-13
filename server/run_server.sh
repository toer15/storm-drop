#!/bin/sh
# Run a Storm Drop dedicated server without Docker (Linux x64).
#   ./run_server.sh                 ENet/UDP on port 7777 (PC + Android players)
#   ./run_server.sh --ws            WebSocket on port 7777 (also lets browser players join)
#   PORT=8000 BOTS=20 ./run_server.sh
cd "$(dirname "$0")/dist" && exec ./StormDrop.x86_64 --headless -- --server --port=${PORT:-7777} --bots=${BOTS:-30} --max=${MAXP:-16} "$@"
