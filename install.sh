#!/bin/bash

# [1/6] 下载 cloudflared
echo "[1/6] 下载 cloudflared..."
curl -L -o cloudflared https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-linux-amd64
chmod +x cloudflared

# [2/6] 启动 cloudflared 隧道
echo "[2/6] 启动 Cloudflare 隧道..."
nohup ./cloudflared tunnel --url http://localhost:12345 --protocol http2 --no-autoupdate > /tmp/cloudflared.log 2>&1 &

# [3/6] 等待隧道启动
echo "[3/6] 等待隧道启动..."
sleep 5

# [4/6] 显示公网地址
echo "[4/6] 隧道公网地址："
grep -Eo 'https://[a-zA-Z0-9.-]+\.trycloudflare\.com' /tmp/cloudflared.log | tail -n 1

# [5/6] 安装 x-ui
echo "[5/6] 安装 x-ui 面板..."
bash <(curl -Ls https://raw.githubusercontent.com/vaxilu/x-ui/master/install.sh) -y
