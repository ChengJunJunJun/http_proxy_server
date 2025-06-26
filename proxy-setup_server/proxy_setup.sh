#!/bin/bash

# 代理服务器配置脚本
# 使用Privoxy作为HTTP代理，转发到日本VPS的SOCKS5代理

# 移除 set -e 以避免脚本在遇到错误时立即退出
# set -e

# 定义错误处理函数
handle_error() {
    echo "⚠ 警告: $1"
    echo "继续执行下一步..."
    return 0
}

# 配置变量 - 请根据实际情况修改
JAPAN_VPS_IP="156.231.117.240"          # 日本VPS的IP地址
JAPAN_VPS_PORT="1080"                      # 日本VPS的SOCKS5端口
JAPAN_VPS_USER="root"             # SSH用户名（如果需要）
PRIVOXY_PORT="8118"                        # 本地Privoxy端口
SSH_TUNNEL_PORT="1080"                     # 本地SSH隧道端口

echo "=== 代理服务器配置开始 ==="

# 检查是否为root或有sudo权限
if [[ $EUID -ne 0 ]] && ! sudo -n true 2>/dev/null; then
    echo "错误: 需要root权限或sudo权限"
    exit 1
fi

# 1. 安装必要软件
echo "1. 安装必要软件..."

# 先修复可能的包依赖问题
echo "修复包依赖问题..."
sudo dpkg --configure -a 2>/dev/null || true
sudo apt-get -f install -y 2>/dev/null || true

# 更新包列表，如果失败也继续
echo "更新包列表..."
sudo apt update || {
    echo "警告: 包列表更新失败，但继续运行..."
}

# 定义必要的包列表
ESSENTIAL_PACKAGES=(
    "privoxy"
    "curl" 
    "wget"
    "openssh-client"
)

# 逐个安装必要包，失败时继续
echo "安装核心包..."
for package in "${ESSENTIAL_PACKAGES[@]}"; do
    echo "正在安装 $package..."
    if sudo apt install -y "$package" 2>/dev/null; then
        echo "✓ $package 安装成功"
    else
        echo "⚠ $package 安装失败，尝试强制安装..."
        sudo apt install -y --fix-broken "$package" 2>/dev/null || {
            echo "✗ $package 安装失败，但继续运行..."
        }
    fi
done

# 检查关键包是否安装成功
echo "检查关键包安装状态..."
CRITICAL_PACKAGES=("privoxy" "curl")
for package in "${CRITICAL_PACKAGES[@]}"; do
    if dpkg -l | grep -q "^ii  $package "; then
        echo "✓ $package 已安装"
    else
        echo "⚠ 尝试使用snap或其他方式安装 $package..."
        case $package in
            "curl")
                # curl通常系统自带或可以通过其他方式安装
                if ! command -v curl >/dev/null 2>&1; then
                    echo "错误: curl是必需的，请手动安装"
                fi
                ;;
            "privoxy")
                echo "错误: privoxy是关键组件，尝试手动安装："
                echo "sudo apt update && sudo apt install -y privoxy"
                ;;
        esac
    fi
done

# 2. 备份原始配置
echo "2. 备份原始配置..."
sudo cp /etc/privoxy/config /etc/privoxy/config.backup.$(date +%Y%m%d_%H%M%S)

# 3. 配置Privoxy
echo "3. 配置Privoxy..."
sudo tee /etc/privoxy/config > /dev/null << EOF
# Privoxy配置文件 - 专用于wandb和github代理

# 基本设置
user-manual /usr/share/doc/privoxy/user-manual
confdir /etc/privoxy
logdir /var/log/privoxy
actionsfile match-all.action
actionsfile default.action
actionsfile user.action
filterfile default.filter
filterfile user.filter
logfile logfile

# 监听地址和端口
listen-address 127.0.0.1:${PRIVOXY_PORT}
listen-address 0.0.0.0:${PRIVOXY_PORT}

# 转发规则 - 只代理特定域名
forward-socks5 .wandb.ai 127.0.0.1:${SSH_TUNNEL_PORT} .
forward-socks5 .github.com 127.0.0.1:${SSH_TUNNEL_PORT} .
forward-socks5 .githubusercontent.com 127.0.0.1:${SSH_TUNNEL_PORT} .
forward-socks5 .githubassets.com 127.0.0.1:${SSH_TUNNEL_PORT} .

# 其他域名直连
forward / .

# 安全设置
toggle 1
enable-remote-toggle 0
enable-remote-http-toggle 0
enable-edit-actions 0

# 日志级别
debug 1
EOF

# 4. 创建用户行为配置
echo "4. 创建用户行为配置..."
sudo tee /etc/privoxy/user.action > /dev/null << 'EOF'
# 用户自定义行为配置

# 对于wandb和github域名，使用代理
{+forward-override{forward-socks5 127.0.0.1:1080 .}}
.wandb.ai
api.wandb.ai
*.wandb.ai
.github.com
*.github.com
.githubusercontent.com
*.githubusercontent.com
.githubassets.com
*.githubassets.com

# 其他域名直连
{+forward-override{forward .}}
*
EOF

# 5. 设置权限
echo "5. 设置权限..."
sudo chown privoxy:privoxy /etc/privoxy/config
sudo chown privoxy:privoxy /etc/privoxy/user.action
sudo chmod 640 /etc/privoxy/config
sudo chmod 640 /etc/privoxy/user.action

# 6. 启动并启用Privoxy服务
echo "6. 启动Privoxy服务..."

# 检查privoxy是否已安装
if ! command -v privoxy >/dev/null 2>&1 && ! dpkg -l | grep -q "^ii  privoxy "; then
    handle_error "Privoxy未安装，跳过服务配置"
else
    # 启用服务
    if sudo systemctl enable privoxy 2>/dev/null; then
        echo "✓ Privoxy服务已启用"
    else
        handle_error "Privoxy服务启用失败"
    fi

    # 重启服务
    if sudo systemctl restart privoxy 2>/dev/null; then
        echo "✓ Privoxy服务已重启"
    else
        handle_error "Privoxy服务重启失败，尝试启动..."
        sudo systemctl start privoxy 2>/dev/null || handle_error "Privoxy服务启动失败"
    fi

    # 等待服务启动
    sleep 3

    # 7. 检查服务状态
    echo "7. 检查Privoxy服务状态..."
    if sudo systemctl is-active --quiet privoxy 2>/dev/null; then
        echo "✓ Privoxy服务运行正常"
    else
        handle_error "Privoxy服务未正常运行，但继续配置其他组件"
        echo "可以稍后手动启动: sudo systemctl start privoxy"
    fi
fi

# 8. 创建SSH隧道管理脚本
echo "8. 创建SSH隧道管理脚本..."
sudo tee /usr/local/bin/ssh-tunnel-manager.sh > /dev/null << EOF
#!/bin/bash

# SSH隧道管理脚本

JAPAN_VPS_IP="${JAPAN_VPS_IP}"
JAPAN_VPS_PORT="${JAPAN_VPS_PORT}"
JAPAN_VPS_USER="${JAPAN_VPS_USER}"
LOCAL_PORT="${SSH_TUNNEL_PORT}"
PID_FILE="/var/run/ssh-tunnel.pid"

case "\$1" in
    start)
        if [ -f "\$PID_FILE" ] && kill -0 \$(cat "\$PID_FILE") 2>/dev/null; then
            echo "SSH隧道已在运行"
            exit 0
        fi
        echo "启动SSH隧道..."
        ssh -f -N -D \${LOCAL_PORT} -o ServerAliveInterval=60 -o ServerAliveCountMax=3 \${JAPAN_VPS_USER}@\${JAPAN_VPS_IP} -p \${JAPAN_VPS_PORT}
        echo \$! > "\$PID_FILE"
        echo "SSH隧道已启动，PID: \$(cat \$PID_FILE)"
        ;;
    stop)
        if [ -f "\$PID_FILE" ]; then
            PID=\$(cat "\$PID_FILE")
            if kill -0 "\$PID" 2>/dev/null; then
                kill "\$PID"
                rm -f "\$PID_FILE"
                echo "SSH隧道已停止"
            else
                echo "SSH隧道进程不存在"
                rm -f "\$PID_FILE"
            fi
        else
            echo "SSH隧道未运行"
        fi
        ;;
    restart)
        \$0 stop
        sleep 2
        \$0 start
        ;;
    status)
        if [ -f "\$PID_FILE" ] && kill -0 \$(cat "\$PID_FILE") 2>/dev/null; then
            echo "SSH隧道正在运行，PID: \$(cat \$PID_FILE)"
        else
            echo "SSH隧道未运行"
        fi
        ;;
    *)
        echo "用法: \$0 {start|stop|restart|status}"
        exit 1
        ;;
esac
EOF

sudo chmod +x /usr/local/bin/ssh-tunnel-manager.sh

# 9. 创建系统服务单元
echo "9. 创建SSH隧道系统服务..."
sudo tee /etc/systemd/system/ssh-tunnel.service > /dev/null << EOF
[Unit]
Description=SSH Tunnel to Japan VPS
After=network.target

[Service]
Type=forking
ExecStart=/usr/local/bin/ssh-tunnel-manager.sh start
ExecStop=/usr/local/bin/ssh-tunnel-manager.sh stop
ExecReload=/usr/local/bin/ssh-tunnel-manager.sh restart
PIDFile=/var/run/ssh-tunnel.pid
Restart=on-failure
RestartSec=10
User=root

[Install]
WantedBy=multi-user.target
EOF

sudo systemctl daemon-reload

# 10. 创建全局代理配置脚本
echo "10. 创建全局代理配置脚本..."
sudo tee /etc/profile.d/selective-proxy.sh > /dev/null << EOF
#!/bin/bash

# 全局选择性代理配置
# 只对wandb和github使用代理

# 代理服务器地址
PROXY_SERVER="http://127.0.0.1:${PRIVOXY_PORT}"

# 设置特定程序的代理
export WANDB_HTTP_PROXY="\$PROXY_SERVER"
export WANDB_HTTPS_PROXY="\$PROXY_SERVER"

# Git代理配置函数
setup_git_proxy() {
    git config --global http.https://github.com.proxy "\$PROXY_SERVER"
    git config --global https.https://github.com.proxy "\$PROXY_SERVER"
}

# 清除Git代理配置函数
clear_git_proxy() {
    git config --global --unset http.https://github.com.proxy 2>/dev/null || true
    git config --global --unset https.https://github.com.proxy 2>/dev/null || true
}

# 创建别名
alias enable-proxy='setup_git_proxy && echo "GitHub代理已启用"'
alias disable-proxy='clear_git_proxy && echo "GitHub代理已禁用"'
alias proxy-status='echo "Privoxy状态: \$(systemctl is-active privoxy)"; echo "SSH隧道状态: \$(/usr/local/bin/ssh-tunnel-manager.sh status)"'

# 自动启用GitHub代理
setup_git_proxy
EOF

sudo chmod +x /etc/profile.d/selective-proxy.sh

echo "=== 配置完成 ==="
echo ""
echo "后续步骤:"
echo "1. 编辑配置: sudo nano $0"
echo "   - 设置 JAPAN_VPS_IP 为你的日本VPS IP地址"
echo "   - 设置 JAPAN_VPS_USER 为SSH用户名"
echo "   - 根据需要调整端口设置"
echo ""
echo "2. 启动SSH隧道: sudo /usr/local/bin/ssh-tunnel-manager.sh start"
echo "3. 启用SSH隧道服务: sudo systemctl enable ssh-tunnel"
echo ""
echo "4. 重新加载环境变量: source /etc/profile.d/selective-proxy.sh"
echo ""
echo "5. 测试代理:"
echo "   - 测试wandb: python -c \"import wandb; print('wandb可用')\""
echo "   - 测试github: git clone https://github.com/octocat/Hello-World.git"
echo ""
echo "管理命令:"
echo "   - 代理状态: proxy-status"
echo "   - 启用GitHub代理: enable-proxy"
echo "   - 禁用GitHub代理: disable-proxy"
echo "   - SSH隧道管理: sudo /usr/local/bin/ssh-tunnel-manager.sh {start|stop|restart|status}"