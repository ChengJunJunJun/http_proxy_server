#!/bin/bash

# 网络配置检查脚本
echo "=== 服务器网络配置检查 ==="

# 1. 检查当前网络接口
echo "1. 网络接口信息:"
ip addr show | grep -E "^[0-9]+:|inet "

# 2. 检查DNS配置
echo -e "\n2. DNS配置:"
cat /etc/resolv.conf

# 3. 检查常用端口占用情况
echo -e "\n3. 常用代理端口占用检查:"
ports=(8080 8118 1080 3128 8888 9999)
for port in "${ports[@]}"; do
    result=$(netstat -tuln | grep ":$port ")
    if [ -n "$result" ]; then
        echo "端口 $port 已被占用: $result"
    else
        echo "端口 $port 可用"
    fi
done

# 4. 检查当前代理设置
echo -e "\n4. 当前环境变量代理设置:"
env | grep -i proxy

# 5. 测试网络连通性
echo -e "\n5. 网络连通性测试:"
echo "测试国内网络 (百度):"
timeout 5 curl -s -I http://www.baidu.com | head -1

echo "测试国际网络 (Google):"
timeout 5 curl -s -I http://www.google.com | head -1

echo "测试 GitHub:"
timeout 5 curl -s -I https://github.com | head -1

echo "测试 wandb:"
timeout 5 curl -s -I https://api.wandb.ai | head -1

# 6. 检查iptables规则
echo -e "\n6. 防火墙规则检查:"
if command -v iptables &> /dev/null; then
    echo "INPUT链规则数量: $(iptables -L INPUT --line-numbers | wc -l)"
    echo "OUTPUT链规则数量: $(iptables -L OUTPUT --line-numbers | wc -l)"
else
    echo "iptables 未安装"
fi

# 7. 检查系统服务
echo -e "\n7. 代理相关服务检查:"
services=(privoxy squid nginx)
for service in "${services[@]}"; do
    if systemctl is-active --quiet $service; then
        echo "$service 服务正在运行"
    else
        echo "$service 服务未运行"
    fi
done

echo -e "\n=== 检查完成 ==="