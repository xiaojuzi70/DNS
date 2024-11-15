#!/bin/bash

# 确保以 root 用户运行
if [ "$EUID" -ne 0 ]; then
  echo "请以 root 用户运行此脚本。"
  exit 1
fi

echo "==== 综合服务器配置工具 ===="
echo "本脚本支持以下功能："
echo "1) 修改 SSH 配置（包括端口和密钥登录）"
echo "2) 配置 Fail2Ban 防护规则"
echo "3) 解封指定 IP"
echo "4) 更新系统源"
echo "5) 配置 DNS"
echo "6) 启用时间同步服务"
echo "7) 退出"
echo

# 功能 1: 修改 SSH 配置
function modify_ssh_config() {
  echo "1. 修改 SSH 配置..."
  SSH_CONFIG="/etc/ssh/sshd_config"
  BACKUP_CONFIG="/etc/ssh/sshd_config.bak"

  if [[ ! -f $BACKUP_CONFIG ]]; then
    echo "备份原始 SSH 配置..."
    cp $SSH_CONFIG $BACKUP_CONFIG
  fi

  # 修改 SSH 端口
  read -p "请输入新的 SSH 端口（默认 2222，留空跳过）：" new_port
  new_port=${new_port:-2222}
  sed -i "s/^#\?Port.*/Port $new_port/" $SSH_CONFIG
  echo "SSH 端口已修改为 $new_port。"

  # 禁用密码登录
  read -p "是否禁用密码登录？(y/n，默认 n)：" disable_password
  disable_password=${disable_password:-n}

  if [[ $disable_password == "y" ]]; then
    sed -i 's/^#\?PasswordAuthentication.*/PasswordAuthentication no/' $SSH_CONFIG
    echo "已禁用密码登录。"
  else
    echo "跳过禁用密码登录。"
  fi

  systemctl restart sshd
  echo "SSH 配置已完成并重启服务！"
}

# 功能 2: 配置 Fail2Ban
function configure_fail2ban() {
  echo "2. 配置 Fail2Ban..."
  if ! command -v fail2ban-server &>/dev/null; then
    echo "Fail2Ban 未安装，正在安装..."
    apt update && apt install -y fail2ban
  fi

  # 输入 Fail2Ban 配置
  read -p "请输入最大尝试次数（默认 3，留空跳过）：" maxretry
  maxretry=${maxretry:-3}

  read -p "请输入封禁时间（秒，默认 86400，留空跳过）：" bantime
  bantime=${bantime:-86400}

  read -p "请输入检测时间窗口（秒，默认 600，留空跳过）：" findtime
  findtime=${findtime:-600}

  # 配置 Fail2Ban
  FAIL2BAN_CONFIG="/etc/fail2ban/jail.local"
  cat > $FAIL2BAN_CONFIG <<EOL
[sshd]
enabled = true
port = $(grep ^Port /etc/ssh/sshd_config | awk '{print $2}')
logpath = /var/log/auth.log
maxretry = $maxretry
bantime = $bantime
findtime = $findtime
EOL

  systemctl restart fail2ban
  echo "Fail2Ban 配置完成！"
}

# 功能 3: 解封 IP
function unban_ip() {
  echo "3. 解封指定 IP..."
  read -p "请输入要解封的 IP 地址：" ip_address

  if [[ -n $ip_address ]]; then
    fail2ban-client unban "$ip_address"
    echo "IP 地址 $ip_address 已解封！"
  else
    echo "跳过解封 IP。"
  fi
}

# 功能 4: 更新系统源
function update_sources() {
  echo "4. 更新系统源..."
  cp /etc/apt/sources.list /etc/apt/sources.list.bak
  DEBIAN_VERSION=$(lsb_release -sc)

  echo "请选择你要使用的系统源 (输入数字选择，留空跳过):"
  echo "1) 官方系统源"
  echo "2) 阿里云源"
  echo "3) 清华大学源"
  echo "4) 火山引擎源"
  read -p "请输入你的选择 (1-4): " SOURCE_CHOICE

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

  apt update
  echo "系统源更新完成！"
}

# 功能 5: 配置 DNS
function configure_dns() {
  echo "5. 配置 DNS..."
  echo "请选择你要使用的 DNS (输入数字选择，留空跳过):"
  echo "1) Google DNS (8.8.8.8, 8.8.4.4)"
  echo "2) Cloudflare DNS (1.1.1.1, 1.0.0.1)"
  echo "3) 阿里云 DNS (223.5.5.5, 223.6.6.6)"
  read -p "请输入你的选择 (1-3): " DNS_CHOICE

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
      echo "跳过配置 DNS。"
      return
      ;;
  esac

  chattr +i /etc/resolv.conf
  echo "DNS 配置完成！"
}

# 功能 6: 启用时间同步
function enable_time_sync() {
  echo "6. 启用时间同步服务..."
  apt install -y systemd-timesyncd
  systemctl enable systemd-timesyncd
  systemctl start systemd-timesyncd

  if timedatectl status | grep "NTP synchronized: yes" > /dev/null; then
    echo "时间同步成功！"
  else
    echo "时间同步失败，请检查 NTP 服务。"
  fi
}

# 主循环
while true; do
  echo
  echo "请选择一个功能进行操作："
  echo "1) 修改 SSH 配置"
  echo "2) 配置 Fail2Ban"
  echo "3) 解封 IP"
  echo "4) 更新系统源"
  echo "5) 配置 DNS"
  echo "6) 启用时间同步"
  echo "7) 退出"
  read -p "请输入选项 (1-7): " choice
  echo

  case $choice in
    1) modify_ssh_config ;;
    2) configure_fail2ban ;;
    3) unban_ip ;;
    4) update_sources ;;
    5) configure_dns ;;
    6) enable_time_sync ;;
    7) echo "退出脚本。"; exit 0 ;;
    *) echo "无效选项，请重新输入。" ;;
  esac
done
