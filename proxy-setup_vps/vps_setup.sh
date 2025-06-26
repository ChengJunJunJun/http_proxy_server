#!/bin/bash

# 日本VPS服务器配置脚本
# 在日本VPS上运行此脚本以设置SOCKS5代理服务

set -e

echo "=== 日本VPS代理服务器配置 ==="

# 检查是否为root用户
if [[ $EUID -ne 0 ]] && ! sudo -n true 2>/dev/null; then
    echo "错误: 需要root权限或sudo权限"
    exit 1
fi

# 1. 更新系统
echo "1. 更新系统包..."
sudo apt update && sudo apt upgrade -y

# 2. 安装必要软件
echo "2. 安装必要软件..."
sudo apt install -y openssh-server ufw fail2ban

# 3. 配置SSH服务
echo "3. 配置SSH服务..."

# 备份原始SSH配置
sudo cp /etc/ssh/sshd_config /etc/ssh/sshd_config.backup.$(date +%Y%m%d_%H%M%S)

# 配置SSH允许端口转发
sudo tee -a /etc/ssh/sshd_config > /dev/null << 'EOF'

# 代理相关配置
AllowTcpForwarding yes
GatewayPorts no
PermitTunnel yes
MaxSessions 10
MaxStartups 10:30:100

# 安全设置
PasswordAuthentication no
PubkeyAuthentication yes
PermitRootLogin no
Protocol 2
ClientAliveInterval 60
ClientAliveCountMax 3
EOF

# 4. 配置防火墙
echo "4. 配置防火墙..."
sudo ufw --force reset
sudo ufw default deny incoming
sudo ufw default allow outgoing

# 允许SSH端口
SSH_PORT=$(grep -E "^#?Port " /etc/ssh/sshd_config | awk '{print $2}' | tail -1)
if [ -z "$SSH_PORT" ]; then
    SSH_PORT="22"
fi
sudo ufw allow $SSH_PORT/tcp comment 'SSH'

# 允许SOCKS5代理端口（只允许本地连接）
sudo ufw allow from 127.0.0.1 to any port 1080 comment 'SOCKS5'

# 启用防火墙
sudo ufw --force enable

# 5. 配置fail2ban
echo "5. 配置fail2ban..."
sudo tee /etc/fail2ban/jail.local > /dev/null << 'EOF'
[DEFAULT]
bantime = 3600
findtime = 600
maxretry = 3

[sshd]
enabled = true
port = ssh
filter = sshd
logpath = /var/log/auth.log
maxretry = 3
bantime = 3600
EOF

# 6. 创建专用用户（可选，但推荐）
echo "6. 创建代理专用用户..."
PROXY_USER="proxyuser"
if ! id "$PROXY_USER" &>/dev/null; then
    sudo adduser --disabled-password --gecos "" $PROXY_USER
    sudo mkdir -p /home/$PROXY_USER/.ssh
    sudo chown $PROXY_USER:$PROXY_USER /home/$PROXY_USER/.ssh
    sudo chmod 700 /home/$PROXY_USER/.ssh
    
    echo "请将客户端的公钥添加到 /home/$PROXY_USER/.ssh/authorized_keys"
    echo "示例命令（在客户端执行）:"
    echo "ssh-copy-id $PROXY_USER@$(curl -s ifconfig.me)"
fi

# 7. 创建连接监控脚本
echo "7. 创建连接监控脚本..."
sudo tee /usr/local/bin/proxy-monitor.sh > /dev/null << 'EOF'
#!/bin/bash

# 代理连接监控脚本

LOG_FILE="/var/log/proxy-monitor.log"

log_message() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') - $1" >> "$LOG_FILE"
}

# 检查SSH连接数
ssh_connections=$(ss -t state established '( dport = :22 )' | grep -c '^ESTAB' || echo "0")
log_message "当前SSH连接数: $ssh_connections"

# 检查SOCKS5端口
socks_connections=$(ss -t state established '( dport = :1080 )' | grep -c '^ESTAB' || echo "0")
log_message "当前SOCKS5连接数: $socks_connections"

# 检查系统负载
load_avg=$(uptime | awk -F'load average:' '{print $2}' | awk '{print $1}' | sed 's/,//')
log_message "系统负载: $load_avg"

# 检查内存使用
memory_usage=$(free | grep Mem | awk '{printf "%.1f", $3/$2 * 100.0}')
log_message "内存使用率: ${memory_usage}%"

# 如果连接数过多，记录警告
if [ "$ssh_connections" -gt 10 ]; then
    log_message "警告: SSH连接数过多 ($ssh_connections)"
fi
EOF

sudo chmod +x /usr/local/bin/proxy-monitor.sh

# 8. 设置定时监控
echo "8. 设置定时监控..."
(crontab -l 2>/dev/null; echo "*/5 * * * * /usr/local/bin/proxy-monitor.sh") | crontab -

# 9. 创建状态检查脚本
echo "9. 创建状态检查脚本..."
sudo tee /usr/local/bin/vps-status.sh > /dev/null << 'EOF'
#!/bin/bash

echo "=== VPS代理服务器状态 ==="

# 基本信息
echo "服务器IP: $(curl -s ifconfig.me)"
echo "服务器时间: $(date)"
echo "系统负载: $(uptime | cut -d',' -f1-3)"

# 服务状态
echo -e "\n服务状态:"
echo "SSH服务: $(systemctl is-active ssh)"
echo "UFW防火墙: $(systemctl is-active ufw)"
echo "Fail2ban: $(systemctl is-active fail2ban)"

# 网络连接
echo -e "\n网络连接:"
echo "SSH连接数: $(ss -t state established '( dport = :22 )' | grep -c '^ESTAB' || echo '0')"
echo "SOCKS5连接数: $(ss -t state established '( dport = :1080 )' | grep -c '^ESTAB' || echo '0')"

# 防火墙状态
echo -e "\n防火墙规则:"
sudo ufw status numbered | head -10

# 系统资源
echo -e "\n系统资源:"
echo "内存使用: $(free -h | grep Mem | awk '{print $3"/"$2}')"
echo "磁盘使用: $(df -h / | tail -1 | awk '{print $3"/"$2" ("$5")"}')"

# 最近的连接日志
echo -e "\n最近的SSH连接 (最后5条):"
grep "Accepted publickey" /var/log/auth.log | tail -5 | cut -d' ' -f1-3,9-11 || echo "无连接记录"

echo -e "\n=== 状态检查完成 ==="
EOF

sudo chmod +x /usr/local/bin/vps-status.sh

# 10. 重启服务
echo "10. 重启相关服务..."
sudo systemctl restart ssh
sudo systemctl restart fail2ban
sudo systemctl enable ssh
sudo systemctl enable fail2ban

echo "=== VPS配置完成 ==="
echo ""
echo "重要信息:"
echo "1. 服务器公网IP: $(curl -s ifconfig.me)"
echo "2. SSH端口: $SSH_PORT"
echo "3. 代理用户: $PROXY_USER (如果创建)"
echo ""
echo "客户端连接命令示例:"
echo "ssh -D 1080 -N -f $PROXY_USER@$(curl -s ifconfig.me)"
echo ""
echo "安全建议:"
echo "1. 定期更新系统: sudo apt update && sudo apt upgrade"
echo "2. 监控连接日志: tail -f /var/log/auth.log"
echo "3. 检查防火墙状态: sudo ufw status"
echo "4. 查看服务状态: /usr/local/bin/vps-status.sh"
echo ""
echo "下一步:"
echo "1. 在客户端生成SSH密钥对: ssh-keygen -t rsa -b 4096"
echo "2. 将公钥复制到VPS: ssh-copy-id $PROXY_USER@$(curl -s ifconfig.me)"
echo "3. 在客户端运行代理配置脚本"