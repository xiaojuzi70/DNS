#!/bin/bash

# 检查是否为root用户
if [ "$EUID" -ne 0 ]; then
  echo "请以root用户运行此脚本。"
  exit
fi

# 备份现有的sources.list
cp /etc/apt/sources.list /etc/apt/sources.list.bak

# 检查Debian版本
DEBIAN_VERSION=$(lsb_release -sc)
if [ "$DEBIAN_VERSION" != "bullseye" ] && [ "$DEBIAN_VERSION" != "bookworm" ]; then
  echo "此脚本仅支持Debian 11 (bullseye) 和 Debian 12 (bookworm)。"
  exit
fi

# 提供用户选择源
echo "请选择你要使用的系统源 (输入数字选择):"
echo "1) 官方系统源"
echo "2) 阿里云源"
echo "3) 清华大学源"
echo "4) 火山引擎源"
read -p "请输入你的选择 (1-4): " SOURCE_CHOICE

# 根据选择更新源
case $SOURCE_CHOICE in
  1)
    echo "使用官方系统源..."
    cat > /etc/apt/sources.list << EOF
deb http://deb.debian.org/debian/ $DEBIAN_VERSION main contrib non-free
deb http://deb.debian.org/debian/ $DEBIAN_VERSION-updates main contrib non-free
deb http://deb.debian.org/debian-security/ $DEBIAN_VERSION-security main contrib non-free
EOF
    ;;
  2)
    echo "使用阿里云源..."
    cat > /etc/apt/sources.list << EOF
deb http://mirrors.aliyun.com/debian/ $DEBIAN_VERSION main contrib non-free
deb http://mirrors.aliyun.com/debian/ $DEBIAN_VERSION-updates main contrib non-free
deb http://mirrors.aliyun.com/debian-security $DEBIAN_VERSION-security main contrib non-free
EOF
    ;;
  3)
    echo "使用清华大学源..."
    cat > /etc/apt/sources.list << EOF
deb https://mirrors.tuna.tsinghua.edu.cn/debian/ $DEBIAN_VERSION main contrib non-free
deb https://mirrors.tuna.tsinghua.edu.cn/debian/ $DEBIAN_VERSION-updates main contrib non-free
deb https://mirrors.tuna.tsinghua.edu.cn/debian-security $DEBIAN_VERSION-security main contrib non-free
EOF
    ;;
  4)
    echo "使用火山引擎源..."
    cat > /etc/apt/sources.list << EOF
deb https://mirrors.volces.com/debian/ $DEBIAN_VERSION main contrib non-free
deb https://mirrors.volces.com/debian/ $DEBIAN_VERSION-updates main contrib non-free
deb https://mirrors.volces.com/debian-security $DEBIAN_VERSION-security main contrib non-free
EOF
    ;;
  *)
    echo "无效选择，退出。"
    exit
    ;;
esac

# 更新系统源
echo "正在更新系统源..."
apt update

# 提供用户选择DNS
echo "请选择你要使用的DNS (输入数字选择):"
echo "1) Google DNS (8.8.8.8, 8.8.4.4)"
echo "2) Cloudflare DNS (1.1.1.1, 1.0.0.1)"
echo "3) 阿里云 DNS (223.5.5.5, 223.6.6.6)"
read -p "请输入你的选择 (1-3): " DNS_CHOICE

# 根据选择配置DNS
case $DNS_CHOICE in
  1)
    echo "使用Google DNS..."
    cat > /etc/resolv.conf << EOF
nameserver 8.8.8.8
nameserver 8.8.4.4
EOF
    ;;
  2)
    echo "使用Cloudflare DNS..."
    cat > /etc/resolv.conf << EOF
nameserver 1.1.1.1
nameserver 1.0.0.1
EOF
    ;;
  3)
    echo "使用阿里云 DNS..."
    cat > /etc/resolv.conf << EOF
nameserver 223.5.5.5
nameserver 223.6.6.6
EOF
    ;;
  *)
    echo "无效选择，退出。"
    exit
    ;;
esac

# 防止resolv.conf被重置
chattr +i /etc/resolv.conf

# 同步时间
echo "正在同步时间..."
timedatectl set-ntp true
if timedatectl status | grep "NTP synchronized: yes" > /dev/null; then
  echo "时间同步成功！"
else
  echo "时间同步失败，请检查 NTP 服务。"
fi

echo "系统源和DNS已成功更新！"

# 显示结束提示
echo "已成功完成源和DNS的更新，建议执行 apt upgrade 来升级系统。"
