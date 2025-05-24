#!/bin/bash

# 安装 cloudflared 最新版本
echo "[1/4] 下载 cloudflared..."
curl -L -o cloudflared https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-linux-amd64
chmod +x cloudflared

# 启动 cloudflared 隧道 (后台运行，写入日志)
echo "[2/4] 启动 Cloudflare 隧道..."
nohup ./cloudflared tunnel --url http://localhost:443 --protocol http2 --no-autoupdate > /tmp/cloudflared.log 2>&1 &

# 等待隧道启动（最多等待5秒）
echo "[3/4] 等待隧道启动..."
sleep 5

# 提取并显示隧道链接
echo "[4/4] 隧道公网地址："
grep -Eo 'https://[a-zA-Z0-9.-]+\.trycloudflare\.com' /tmp/cloudflared.log | tail -n 1
