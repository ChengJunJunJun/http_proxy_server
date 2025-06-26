#!/bin/bash

# 代理测试脚本

echo "=== 代理功能测试 ==="

# 1. 检查服务状态
echo "1. 检查服务状态:"
echo "Privoxy服务: $(systemctl is-active privoxy)"
echo "SSH隧道服务: $(systemctl is-active ssh-tunnel 2>/dev/null || echo 'not-configured')"

# 2. 检查端口监听
echo -e "\n2. 检查端口监听:"
netstat -tuln | grep -E ":8118|:1080" || echo "代理端口未监听"

# 3. 测试直连网络
echo -e "\n3. 测试直连网络(应该正常):"
echo -n "百度: "
timeout 5 curl -s -I http://www.baidu.com | head -1 | cut -d' ' -f2 || echo "失败"

# 4. 测试通过代理访问
echo -e "\n4. 测试代理访问:"
PROXY="http://127.0.0.1:8118"

echo -n "GitHub (通过代理): "
timeout 10 curl -s -I --proxy "$PROXY" https://github.com | head -1 | cut -d' ' -f2 || echo "失败"

echo -n "wandb API (通过代理): "
timeout 10 curl -s -I --proxy "$PROXY" https://api.wandb.ai | head -1 | cut -d' ' -f2 || echo "失败"

# 5. 测试Python wandb
echo -e "\n5. 测试Python wandb连接:"
if command -v python3 &> /dev/null; then
    python3 -c "
import os
os.environ['WANDB_HTTP_PROXY'] = 'http://127.0.0.1:8118'
os.environ['WANDB_HTTPS_PROXY'] = 'http://127.0.0.1:8118'
try:
    import wandb
    # 测试连接但不初始化项目
    print('wandb模块导入成功')
    # 可以尝试测试连接
    # wandb.login(anonymous='allow')
    # print('wandb连接测试成功')
except Exception as e:
    print(f'wandb测试失败: {e}')
"
else
    echo "Python3未安装，跳过wandb测试"
fi

# 6. 测试Git代理
echo -e "\n6. 测试Git代理设置:"
git config --global --get http.https://github.com.proxy || echo "Git代理未设置"

# 7. 显示日志
echo -e "\n7. 查看Privoxy日志(最后10行):"
if [ -f /var/log/privoxy/logfile ]; then
    tail -10 /var/log/privoxy/logfile
else
    echo "Privoxy日志文件不存在"
fi

echo -e "\n=== 测试完成 ==="

# 提供故障排除信息
echo -e "\n故障排除:"
echo "1. 如果代理访问失败，检查SSH隧道是否正常:"
echo "   sudo /usr/local/bin/ssh-tunnel-manager.sh status"
echo ""
echo "2. 重启服务:"
echo "   sudo systemctl restart privoxy"
echo "   sudo /usr/local/bin/ssh-tunnel-manager.sh restart"
echo ""
echo "3. 查看详细日志:"
echo "   sudo journalctl -u privoxy -f"
echo "   sudo tail -f /var/log/privoxy/logfile"