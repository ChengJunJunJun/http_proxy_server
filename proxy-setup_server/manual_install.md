# 手动安装指南

如果自动安装脚本遇到包依赖问题，可以按照以下步骤手动安装：

## 1. 修复系统包依赖问题

```bash
# 修复损坏的包
sudo dpkg --configure -a
sudo apt-get -f install

# 清理包缓存
sudo apt clean
sudo apt autoclean

# 更新包列表
sudo apt update
```

## 2. 手动安装关键包

```bash
# 只安装代理必需的包
sudo apt install -y privoxy
sudo apt install -y curl wget openssh-client

# 如果privoxy安装失败，尝试：
sudo apt install -y --fix-broken privoxy
```

## 3. 检查安装状态

```bash
# 检查privoxy是否安装成功
dpkg -l | grep privoxy
which privoxy

# 检查服务状态
sudo systemctl status privoxy
```

## 4. 如果仍然失败

如果包安装持续失败，可以：

1. **跳过有问题的包**：编辑 `proxy_setup.sh`，注释掉安装失败的包
2. **使用容器**：考虑在Docker容器中运行代理服务
3. **使用其他代理软件**：如果privoxy无法安装，可以考虑使用其他HTTP代理软件

## 5. 最小化配置

如果只需要SSH隧道功能，可以直接运行：

```bash
# 手动创建SSH隧道
ssh -D 1080 -N -f user@your-vps-ip

# 配置应用使用SOCKS5代理
export http_proxy=socks5://127.0.0.1:1080
export https_proxy=socks5://127.0.0.1:1080
```

## 6. 故障排除

```bash
# 查看详细错误信息
sudo apt install -y privoxy --verbose

# 检查系统日志
sudo journalctl -u apt-daily
sudo tail -f /var/log/dpkg.log
``` 