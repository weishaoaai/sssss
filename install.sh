#!/bin/bash

curl -L -o cloudflared https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-linux-amd64
chmod +x cloudflared

nohup ./cloudflared tunnel --url http://localhost:12345 --protocol http2 --no-autoupdate > /tmp/cloudflared.log 2>&1 &

sleep 5

echo "隧道公网地址："
grep -Eo 'https://[a-zA-Z0-9.-]+\.trycloudflare\.com' /tmp/cloudflared.log | tail -n 1
