#!/bin/bash
# Local online test: one dedicated headless server + two headless clients on 127.0.0.1.
# usage: tools/nettest.sh [godot binary] [--enet|--ws]   (prints each peer's [nettest] lines)
G=${1:-godot}; PROTO=${2:---enet}   # second arg: --enet (default) or --ws; cd "$(dirname "$0")/.."
P=$((7700 + RANDOM % 200))
$G --headless --path . -- --server --port=$P --bots=6 $PROTO --nettest > /tmp/sd_server.log 2>&1 &
S=$!; sleep 2
$G --headless --path . -- --join=127.0.0.1:$P --player-name=Alice --autoready --nettest $PROTO > /tmp/sd_c1.log 2>&1 &
C1=$!
$G --headless --path . -- --join=127.0.0.1:$P --player-name=Bob --autoready --nettest $PROTO > /tmp/sd_c2.log 2>&1 &
C2=$!
sleep ${WAIT:-45}
kill $S $C1 $C2 2>/dev/null; wait 2>/dev/null
for f in server c1 c2; do echo "===== $f"; grep -E "\[net\]|\[server\]|\[nettest|SCRIPT ERROR|ERROR" /tmp/sd_$f.log | grep -v "mesh_storage\|Parameter \"m\"\|resources still in use\|ObjectDB\|at: " | head -40; done
