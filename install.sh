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
bash <(curl -Ls https://raw.githubusercontent.com/vaxilu/x-ui/master/install.sh)

# [6/6] 配置默认账号密码端口（需 sqlite3 支持）
echo "[6/6] 配置 x-ui 面板账号密码和端口..."

# 安装 sqlite3
apt-get update -y && apt-get install -y sqlite3

# 修改端口、账号密码
DB_FILE="/etc/x-ui/x-ui.db"
if [ -f "$DB_FILE" ]; then
  sqlite3 $DB_FILE "UPDATE setting SET port = 12345;"
  sqlite3 $DB_FILE "UPDATE user SET username = '1', password = '1';"
  systemctl restart x-ui
  echo "✅ x-ui 面板配置完成：端口12345，账号1，密码1"
else
  echo "❌ 配置失败，未找到数据库文件：$DB_FILE"
fi
