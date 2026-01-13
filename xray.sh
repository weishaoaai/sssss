#!/bin/bash

#==========================================
# Xray + Cloudflared 一键安装脚本
# 支持临时隧道和 Token 模式
# 自动检测已安装组件,跳过重复安装
#==========================================

set -e  # 遇到错误立即退出

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# 工作目录（使用当前目录）
WORK_DIR="$(pwd)/xray_cloudflared"
XRAY_BIN="$WORK_DIR/xray"
CLOUDFLARED_BIN="$WORK_DIR/cloudflared"
CONFIG_FILE="$WORK_DIR/config.json"
TOKEN_FILE="$WORK_DIR/.cloudflared_token"

# 日志函数
log_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

log_blue() {
    echo -e "${BLUE}[INPUT]${NC} $1"
}

# 创建工作目录
create_work_dir() {
    if [ ! -d "$WORK_DIR" ]; then
        log_info "创建工作目录: $WORK_DIR"
        mkdir -p "$WORK_DIR"
    else
        log_warn "工作目录已存在,跳过创建"
    fi
    cd "$WORK_DIR"
}

# 安装 Xray
install_xray() {
    if [ -f "$XRAY_BIN" ]; then
        log_warn "Xray 已安装,跳过下载"
        return 0
    fi

    log_info "开始下载 Xray..."
    
    # 下载最新版本
    if wget -q --show-progress -O Xray-linux-64.zip \
        "https://github.com/XTLS/Xray-core/releases/latest/download/Xray-linux-64.zip"; then
        log_info "Xray 下载成功,开始解压..."
        unzip -q -o Xray-linux-64.zip
        chmod +x xray
        rm -f Xray-linux-64.zip
        log_info "Xray 安装完成"
    else
        log_error "Xray 下载失败,请检查网络连接"
        exit 1
    fi
}

# 创建配置文件
create_config() {
    if [ -f "$CONFIG_FILE" ]; then
        log_warn "配置文件已存在,跳过创建"
        return 0
    fi

    log_info "创建 Xray 配置文件..."
    
    # 生成随机 UUID
    UUID=$(cat /proc/sys/kernel/random/uuid)
    
    cat > "$CONFIG_FILE" <<'EOF'
{
  "log": {
    "loglevel": "warning"
  },
  "dns": {
    "servers": ["8.8.8.8"]
  },
  "inbounds": [
    {
      "port": 8080,
      "protocol": "vless",
      "settings": {
        "clients": [
          {
            "id": "UUID_PLACEHOLDER",
            "flow": ""
          }
        ],
        "decryption": "none"
      },
      "streamSettings": {
        "network": "ws",
        "wsSettings": {
          "path": "/404",
          "headers": {}
        }
      },
      "sniffing": {
        "enabled": true,
        "destOverride": ["http", "tls"]
      }
    }
  ],
  "outbounds": [
    {
      "protocol": "freedom",
      "settings": {
        "domainStrategy": "UseIP"
      }
    }
  ]
}
EOF

    # 替换 UUID
    sed -i "s/UUID_PLACEHOLDER/$UUID/g" "$CONFIG_FILE"
    
    log_info "配置文件创建完成"
    log_info "生成的 UUID: $UUID"
}

# 安装 Cloudflared
install_cloudflared() {
    if [ -f "$CLOUDFLARED_BIN" ]; then
        log_warn "Cloudflared 已安装,跳过下载"
        return 0
    fi

    log_info "开始下载 Cloudflared..."
    
    if wget -q --show-progress -O cloudflared \
        "https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-linux-amd64"; then
        chmod +x cloudflared
        log_info "Cloudflared 安装完成"
    else
        log_error "Cloudflared 下载失败,请检查网络连接"
        exit 1
    fi
}

# 启动 Xray
start_xray() {
    # 检查是否已经运行
    if pgrep -f "xray.*$CONFIG_FILE" > /dev/null; then
        log_warn "Xray 已在运行,先停止旧进程..."
        pkill -f "xray.*$CONFIG_FILE" || true
        sleep 2
    fi

    log_info "启动 Xray 服务..."
    nohup "$XRAY_BIN" -config "$CONFIG_FILE" > "$WORK_DIR/xray.log" 2>&1 &
    
    sleep 2
    
    if pgrep -f "xray.*$CONFIG_FILE" > /dev/null; then
        log_info "Xray 启动成功 (PID: $(pgrep -f 'xray.*$CONFIG_FILE'))"
    else
        log_error "Xray 启动失败,查看日志: tail -f $WORK_DIR/xray.log"
        exit 1
    fi
}

# 选择隧道模式
choose_tunnel_mode() {
    echo ""
    echo -e "${BLUE}========================================${NC}"
    echo -e "${BLUE}请选择 Cloudflared 隧道模式:${NC}"
    echo -e "${BLUE}========================================${NC}"
    echo -e "1) 临时隧道 (trycloudflare.com)"
    echo -e "   - 无需注册,即开即用"
    echo -e "   - 域名每次重启会变化"
    echo -e "   - 适合临时测试使用"
    echo ""
    echo -e "2) Token 模式 (固定域名)"
    echo -e "   - 需要 Cloudflare 账号"
    echo -e "   - 域名固定不变"
    echo -e "   - 适合长期使用"
    echo ""
    
    # 检查是否已保存 token
    if [ -f "$TOKEN_FILE" ]; then
        echo -e "${YELLOW}检测到已保存的 Token${NC}"
        echo -e "3) 使用已保存的 Token"
        echo ""
    fi
    
    read -p "请输入选项 (1/2/3): " mode_choice
    echo ""
    
    case $mode_choice in
        1)
            TUNNEL_MODE="temporary"
            ;;
        2)
            TUNNEL_MODE="token"
            input_token
            ;;
        3)
            if [ -f "$TOKEN_FILE" ]; then
                TUNNEL_MODE="token"
                CLOUDFLARE_TOKEN=$(cat "$TOKEN_FILE")
                log_info "使用已保存的 Token"
            else
                log_error "未找到保存的 Token,请选择选项 2"
                exit 1
            fi
            ;;
        *)
            log_error "无效选项,退出"
            exit 1
            ;;
    esac
}

# 输入 Token
input_token() {
    echo -e "${BLUE}========================================${NC}"
    echo -e "${BLUE}如何获取 Cloudflare Tunnel Token:${NC}"
    echo -e "${BLUE}========================================${NC}"
    echo "1. 访问 https://one.dash.cloudflare.com/"
    echo "2. 登录你的 Cloudflare 账号"
    echo "3. 进入 Zero Trust > Networks > Tunnels"
    echo "4. 创建新隧道或选择现有隧道"
    echo "5. 在安装页面找到类似以下命令:"
    echo "   cloudflared tunnel run --token eyJhxxxx..."
    echo "6. 复制 --token 后面的完整字符串"
    echo ""
    
    read -p "请输入你的 Cloudflare Tunnel Token: " CLOUDFLARE_TOKEN
    
    if [ -z "$CLOUDFLARE_TOKEN" ]; then
        log_error "Token 不能为空"
        exit 1
    fi
    
    # 验证 token 格式 (基本检查)
    if [[ ! "$CLOUDFLARE_TOKEN" =~ ^eyJ ]]; then
        log_warn "Token 格式可能不正确,通常以 'eyJ' 开头"
        read -p "是否继续? (y/n): " continue_choice
        if [ "$continue_choice" != "y" ]; then
            exit 1
        fi
    fi
    
    # 保存 token
    echo "$CLOUDFLARE_TOKEN" > "$TOKEN_FILE"
    chmod 600 "$TOKEN_FILE"
    log_info "Token 已保存到 $TOKEN_FILE"
}

# 启动 Cloudflared 隧道 (临时模式)
start_cloudflared_temporary() {
    # 检查是否已经运行
    if pgrep -f "cloudflared tunnel" > /dev/null; then
        log_warn "Cloudflared 已在运行,先停止旧进程..."
        pkill -f "cloudflared tunnel" || true
        sleep 2
    fi

    log_info "启动 Cloudflared 临时隧道..."
    
    # 清空旧日志
    > "$WORK_DIR/cloudflared.log"
    
    # 启动隧道
    nohup "$CLOUDFLARED_BIN" tunnel --url http://127.0.0.1:8080 --no-autoupdate > "$WORK_DIR/cloudflared.log" 2>&1 &
    
    log_info "等待隧道建立..."
    sleep 5
    
    # 提取隧道链接
    TUNNEL_URL=$(grep -oE 'https?://[A-Za-z0-9._-]+\.trycloudflare\.com' "$WORK_DIR/cloudflared.log" | head -n1)
    
    if [ -n "$TUNNEL_URL" ]; then
        log_info "Cloudflared 隧道启动成功!"
        echo -e "${GREEN}========================================${NC}"
        echo -e "${GREEN}临时隧道地址: ${YELLOW}$TUNNEL_URL${NC}"
        echo -e "${GREEN}========================================${NC}"
    else
        log_warn "未能提取隧道地址,请查看日志:"
        tail -n 20 "$WORK_DIR/cloudflared.log"
    fi
}

# 启动 Cloudflared 隧道 (Token 模式)
start_cloudflared_token() {
    # 检查是否已经运行
    if pgrep -f "cloudflared tunnel" > /dev/null; then
        log_warn "Cloudflared 已在运行,先停止旧进程..."
        pkill -f "cloudflared tunnel" || true
        sleep 2
    fi

    log_info "启动 Cloudflared Token 隧道..."
    
    # 清空旧日志
    > "$WORK_DIR/cloudflared.log"
    
    # 使用 token 启动隧道
    nohup "$CLOUDFLARED_BIN" tunnel run --token "$CLOUDFLARE_TOKEN" > "$WORK_DIR/cloudflared.log" 2>&1 &
    
    log_info "等待隧道建立..."
    sleep 5
    
    # 检查是否成功
    if pgrep -f "cloudflared tunnel" > /dev/null; then
        log_info "Cloudflared Token 隧道启动成功!"
        echo -e "${GREEN}========================================${NC}"
        echo -e "${GREEN}隧道已连接到你的 Cloudflare 域名${NC}"
        echo -e "${GREEN}请在 Cloudflare Dashboard 查看域名${NC}"
        echo -e "${GREEN}========================================${NC}"
    else
        log_error "隧道启动失败,请查看日志:"
        tail -n 20 "$WORK_DIR/cloudflared.log"
        exit 1
    fi
}

# 显示连接信息
show_connection_info() {
    echo ""
    echo -e "${GREEN}=== 安装完成 ===${NC}"
    echo -e "工作目录: $WORK_DIR"
    echo -e "Xray 日志: $WORK_DIR/xray.log"
    echo -e "Cloudflared 日志: $WORK_DIR/cloudflared.log"
    echo ""
    
    # 提取 UUID
    UUID=$(grep -oP '"id":\s*"\K[^"]+' "$CONFIG_FILE" | head -n1)
    
    if [ "$TUNNEL_MODE" = "temporary" ]; then
        # 临时隧道模式
        TUNNEL_URL=$(grep -oE 'https?://[A-Za-z0-9._-]+\.trycloudflare\.com' "$WORK_DIR/cloudflared.log" | head -n1)
        
        if [ -n "$TUNNEL_URL" ] && [ -n "$UUID" ]; then
            # 移除 https://
            DOMAIN=${TUNNEL_URL#https://}
            
            echo -e "${GREEN}=== VLESS 连接信息 ===${NC}"
            echo -e "协议: VLESS"
            echo -e "地址: ${YELLOW}$DOMAIN${NC}"
            echo -e "端口: ${YELLOW}443${NC}"
            echo -e "UUID: ${YELLOW}$UUID${NC}"
            echo -e "传输: ${YELLOW}WebSocket${NC}"
            echo -e "路径: ${YELLOW}/404${NC}"
            echo -e "TLS: ${YELLOW}启用${NC}"
            echo ""
            echo -e "${GREEN}=== VLESS 链接 ===${NC}"
            echo -e "${YELLOW}vless://$UUID@162.159.62.216:443?encryption=none&security=tls&sni=$DOMAIN&type=ws&host=$DOMAIN&path=%2F404#CloudflareXray${NC}"
        fi
    else
        # Token 模式
        echo -e "${GREEN}=== VLESS 连接信息 ===${NC}"
        echo -e "协议: VLESS"
        echo -e "地址: ${YELLOW}你的 Cloudflare 域名${NC}"
        echo -e "端口: ${YELLOW}443${NC}"
        echo -e "UUID: ${YELLOW}$UUID${NC}"
        echo -e "传输: ${YELLOW}WebSocket${NC}"
        echo -e "路径: ${YELLOW}/404${NC}"
        echo -e "TLS: ${YELLOW}启用${NC}"
        echo ""
        echo -e "${YELLOW}请在 Cloudflare Zero Trust Dashboard 中配置:${NC}"
        echo -e "1. Public Hostname: 你的域名"
        echo -e "2. Service: http://localhost:8080"
        echo -e "3. 保存配置后使用你的域名连接"
    fi
    
    echo ""
    echo -e "${GREEN}常用命令:${NC}"
    echo -e "查看 Xray 进程: ${YELLOW}ps -ef | grep xray${NC}"
    echo -e "查看 Cloudflared 进程: ${YELLOW}ps -ef | grep cloudflared${NC}"
    echo -e "停止 Xray: ${YELLOW}pkill -f xray${NC}"
    echo -e "停止 Cloudflared: ${YELLOW}pkill -f cloudflared${NC}"
    echo -e "查看 Xray 日志: ${YELLOW}tail -f $WORK_DIR/xray.log${NC}"
    echo -e "查看 Cloudflared 日志: ${YELLOW}tail -f $WORK_DIR/cloudflared.log${NC}"
    
    if [ "$TUNNEL_MODE" = "temporary" ]; then
        echo -e "查看临时隧道地址: ${YELLOW}grep trycloudflare $WORK_DIR/cloudflared.log${NC}"
    fi
    
    echo ""
    echo -e "${GREEN}=== 目录结构 ===${NC}"
    echo -e "$WORK_DIR/"
    echo -e "├── xray              # Xray 二进制文件"
    echo -e "├── cloudflared       # Cloudflared 二进制文件"
    echo -e "├── config.json       # Xray 配置文件"
    echo -e "├── xray.log         # Xray 日志"
    echo -e "├── cloudflared.log  # Cloudflared 日志"
    echo -e "└── .cloudflared_token # Token 文件(如果使用)"
}

# 主函数
main() {
    log_info "=== Xray + Cloudflared 一键安装脚本 ==="
    log_info "工作目录: $WORK_DIR"
    
    create_work_dir
    install_xray
    create_config
    install_cloudflared
    start_xray
    choose_tunnel_mode
    
    if [ "$TUNNEL_MODE" = "temporary" ]; then
        start_cloudflared_temporary
    else
        start_cloudflared_token
    fi
    
    show_connection_info
    
    log_info "所有操作完成!"
}

# 执行主函数
main
