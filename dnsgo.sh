#!/bin/bash

red='\033[0;31m'
green='\033[0;32m'
yellow='\033[0;33m'
plain='\033[0m'

# 确保以 root 用户运行
if [ "$EUID" -ne 0 ]; then
  echo -e "${red}错误：${plain} 请以 root 用户运行此脚本。"
  exit 1
fi

echo -e "${green}==== 综合服务器配置工具 ====${plain}"
echo "本脚本支持以下功能："
echo "1) 修改 SSH 配置（包括端口和密钥登录）"
echo "2) 配置 Fail2Ban 防护规则"
echo "3) 解封指定 IP"
echo "4) 更新系统源"
echo "5) 配置 DNS"
echo "6) 启用时间同步服务"
echo "7) 退出"
echo

# 让我们为每个选项提供默认选择，以防万一输入问题
DEFAULT_SSH_PORT=2222
DEFAULT_PASSWORD_AUTH="n"
DEFAULT_FAIL2BAN_MAXRETRY=3
DEFAULT_FAIL2BAN_BANTIME=86400
DEFAULT_FAIL2BAN_FINDTIME=600
DEFAULT_DNS_CHOICE=1

# 功能 1: 修改 SSH 配置
function modify_ssh_config() {
  echo -e "${yellow}1. 修改 SSH 配置...${plain}"
  SSH_CONFIG="/etc/ssh/sshd_config"
  BACKUP_CONFIG="/etc/ssh/sshd_config.bak"

  if [[ ! -f $BACKUP_CONFIG ]]; then
    echo "备份原始 SSH 配置..."
    cp $SSH_CONFIG $BACKUP_CONFIG
  fi

  echo -n "请输入新的 SSH 端口（默认 $DEFAULT_SSH_PORT，留空跳过）："
  read -r new_port
  new_port=${new_port:-$DEFAULT_SSH_PORT}

  sed -i "s/^#\?Port.*/Port $new_port/" $SSH_CONFIG
  echo "SSH 端口已修改为 $new_port。"

  echo -n "是否禁用密码登录？(y/n，默认 $DEFAULT_PASSWORD_AUTH)："
  read -r disable_password
  disable_password=${disable_password:-$DEFAULT_PASSWORD_AUTH}

  if [[ $disable_password == "y" ]]; then
    sed -i 's/^#\?PasswordAuthentication.*/PasswordAuthentication no/' $SSH_CONFIG
    echo "已禁用密码登录。"
  else
    echo "跳过禁用密码登录。"
  fi

  if systemctl restart sshd; then
    echo "SSH 服务重启成功！"
  else
    echo "SSH 服务重启失败！"
  fi
}

# 功能 2: 配置 Fail2Ban
function configure_fail2ban() {
  echo -e "${yellow}2. 配置 Fail2Ban...${plain}"
  FAIL2BAN_CONFIG="/etc/fail2ban/jail.local"

  if ! command -v fail2ban-server &>/dev/null; then
    echo "Fail2Ban 未安装，正在安装..."
    apt update || { echo "更新源失败"; exit 1; }
    apt install -y fail2ban || { echo "安装 Fail2Ban 失败"; exit 1; }
  fi

  echo -n "请输入最大尝试次数（默认 $DEFAULT_FAIL2BAN_MAXRETRY，留空跳过）："
  read -r maxretry
  maxretry=${maxretry:-$DEFAULT_FAIL2BAN_MAXRETRY}

  echo -n "请输入封禁时间（秒，默认 $DEFAULT_FAIL2BAN_BANTIME，留空跳过）："
  read -r bantime
  bantime=${bantime:-$DEFAULT_FAIL2BAN_BANTIME}

  echo -n "请输入检测时间窗口（秒，默认 $DEFAULT_FAIL2BAN_FINDTIME，留空跳过）："
  read -r findtime
  findtime=${findtime:-$DEFAULT_FAIL2BAN_FINDTIME}

  cat > $FAIL2BAN_CONFIG <<EOL
[sshd]
enabled = true
port = $(grep ^Port /etc/ssh/sshd_config | awk '{print $2}')
logpath = /var/log/auth.log
maxretry = $maxretry
bantime = $bantime
findtime = $findtime
EOL

  systemctl restart fail2ban || { echo "Fail2Ban 服务重启失败"; exit 1; }
  echo "Fail2Ban 配置完成！"
}

# 功能 3: 解封 IP
function unban_ip() {
  echo -e "${yellow}3. 解封指定 IP...${plain}"
  echo -n "请输入要解封的 IP 地址（留空跳过）："
  read -r ip_address

  if [[ -n $ip_address ]]; then
    if systemctl is-active --quiet fail2ban; then
      fail2ban-client unban "$ip_address"
      echo "IP 地址 $ip_address 已解封！"
    else
      echo "Fail2Ban 未启动，无法解封 IP。"
    fi
  else
    echo "跳过解封 IP。"
  fi
}

# 功能 4: 更新系统源
function update_sources() {
  echo -e "${yellow}4. 更新系统源...${plain}"
  cp /etc/apt/sources.list /etc/apt/sources.list.bak
  DEBIAN_VERSION=$(lsb_release -sc)

  echo "请选择你要使用的系统源 (输入数字选择，留空跳过):"
  echo "1) 官方系统源"
  echo "2) 阿里云源"
  echo "3) 清华大学源"
  echo "4) 火山引擎源"
  read -p "请输入你的选择 (1-4，默认 $DEFAULT_SSH_PORT): " SOURCE_CHOICE
  SOURCE_CHOICE=${SOURCE_CHOICE:-1}

  case $SOURCE_CHOICE in
    1)
      cat > /etc/apt/sources.list << EOF
deb http://deb.debian.org/debian/ $DEBIAN_VERSION main contrib non-free
deb http://deb.debian.org/debian/ $DEBIAN_VERSION-updates main contrib non-free
deb http://deb.debian.org/debian-security/ $DEBIAN_VERSION-security main contrib non-free
EOF
      ;;
    2)
      cat > /etc/apt/sources.list << EOF
deb http://mirrors.aliyun.com/debian/ $DEBIAN_VERSION main contrib non-free
deb http://mirrors.aliyun.com/debian/ $DEBIAN_VERSION-updates main contrib non-free
deb http://mirrors.aliyun.com/debian-security $DEBIAN_VERSION-security main contrib non-free
EOF
      ;;
    3)
      cat > /etc/apt/sources.list << EOF
deb https://mirrors.tuna.tsinghua.edu.cn/debian/ $DEBIAN_VERSION main contrib non-free
deb https://mirrors.tuna.tsinghua.edu.cn/debian/ $DEBIAN_VERSION-updates main contrib non-free
deb https://mirrors.tuna.tsinghua.edu.cn/debian-security $DEBIAN_VERSION-security main contrib non-free
EOF
      ;;
    4)
      cat > /etc/apt/sources.list << EOF
deb https://mirrors.volces.com/debian/ $DEBIAN_VERSION main contrib non-free
deb https://mirrors.volces.com/debian/ $DEBIAN_VERSION-updates main contrib non-free
deb https://mirrors.volces.com/debian-security $DEBIAN_VERSION-security main contrib non-free
EOF
      ;;
    *)
      echo "跳过更新系统源。"
      return
      ;;
  esac

  apt update || { echo "更新源失败"; exit 1; }
  echo "系统源更新完成！"
}

# 功能 5: 配置 DNS
function configure_dns() {
  echo -e "${yellow}5. 配置 DNS...${plain}"
  echo "请选择你要使用的 DNS (输入数字选择，留空跳过):"
  echo "1) Google DNS (8.8.8.8, 8.8.4.4)"
  echo "2) Cloudflare DNS (1.1.1.1, 1.0.0.1)"
  echo "3) 阿里云 DNS (223.5.5.5, 223.6.6.6)"
  read -p "请输入你的选择 (1-3，默认 $DEFAULT_DNS_CHOICE): " DNS_CHOICE
  DNS_CHOICE=${DNS_CHOICE:-$DEFAULT_DNS_CHOICE}

  case $DNS_CHOICE in
    1)
      cat > /etc/resolv.conf << EOF
nameserver 8.8.8.8
nameserver 8.8.4.4
EOF
      ;;
    2)
      cat > /etc/resolv.conf << EOF
nameserver 1.1.1.1
nameserver 1.0.0.1
EOF
      ;;
    3)
      cat > /etc/resolv.conf << EOF
nameserver 223.5.5.5
nameserver 223.6.6.6
EOF
      ;;
    *)
      echo
