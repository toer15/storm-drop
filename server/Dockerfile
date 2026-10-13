# Storm Drop dedicated server (headless Godot 4.3 Linux export).
# The release asset StormDrop-<tag>-Server-Linux-x64.zip already has this layout:  Dockerfile, fly.toml, run_server.sh, dist/StormDrop.x86_64
#   docker build -t storm-drop-server .
#   docker run -d -p 7777:7777/udp -p 7777:7777/tcp storm-drop-server                 # ENet (PC + Android)
#   docker run -d -p 7777:7777/tcp -e PROTO=--ws storm-drop-server                      # WebSocket (PC + Android + browsers)
FROM ubuntu:22.04
RUN apt-get update && apt-get install -y --no-install-recommends ca-certificates libfontconfig1 && rm -rf /var/lib/apt/lists/*
WORKDIR /srv/stormdrop
COPY dist/ ./
RUN chmod +x StormDrop.x86_64
ENV PORT=7777 BOTS=30 MAXP=16 PROTO=--enet
EXPOSE 7777/udp 7777/tcp
CMD ["sh", "-c", "./StormDrop.x86_64 --headless -- --server --port=$PORT --bots=$BOTS --max=$MAXP $PROTO"]
