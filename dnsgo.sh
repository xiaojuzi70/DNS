#!/bin/bash

# 颜色定义
red='\033[0;31m'
green='\033[0;32m'
yellow='\033[0;33m'
blue='\033[0;34m'
plain='\033[0m'

# 日志文件
LOG_FILE="/var/log/server_config.log"

# 写入日志函数
log() {
    echo "$(date "+%Y-%m-%d %H:%M:%S") $1" >> "$LOG_FILE"
    echo -e "$1"
}

# 错误处理函数
error() {
    log "${red}错误：$1${plain}"
    exit 1
}

# 检查系统函数
check_system() {
    if [[ -f /etc/redhat-release ]]; then
        error "当前脚本仅支持 Debian/Ubuntu 系统"
    fi
    
    if ! command -v apt &> /dev/null; then
        error "未找到 apt 包管理器，请确认系统类型"
    fi
}

# 初始化函数
init_system() {
    [[ $EUID -ne 0 ]] && error "请以 root 用户运行此脚本"
    
    # 创建日志目录
    mkdir -p "$(dirname "$LOG_FILE")"
    touch "$LOG_FILE"
    
    # 检查并安装基础工具
    local tools=(curl wget ufw net-tools)
    for tool in "${tools[@]}"; do
        if ! command -v "$tool" &> /dev/null; then
            log "正在安装 $tool..."
            apt update && apt install -y "$tool" || error "安装 $tool 失败"
        fi
    done
}

# 备份函数
backup_config() {
    local file=$1
    local backup_dir="/root/server_config_backup/$(date +%Y%m%d)"
    mkdir -p "$backup_dir"
    cp "$file" "$backup_dir/" || error "备份 $file 失败"
    log "已备份 $file 到 $backup_dir"
}

# 修改 SSH 配置
modify_ssh_config() {
    log "${yellow}正在配置 SSH...${plain}"
    local ssh_config="/etc/ssh/sshd_config"
    
    # 备份配置
    backup_config "$ssh_config"
    
    # 配置 SSH 端口
    read -p "请输入新的 SSH 端口（留空使用 2222）: " new_port
    new_port=${new_port:-2222}
    if ! [[ "$new_port" =~ ^[0-9]+$ ]] || [ "$new_port" -lt 1 ] || [ "$new_port" -gt 65535 ]; then
        error "无效的端口号"
    fi
    
    # 配置密钥登录
    read -p "是否禁用密码登录？(y/n): " disable_passwd
    case "$disable_passwd" in
        [yY])
            sed -i 's/^#\?PasswordAuthentication.*/PasswordAuthentication no/' "$ssh_config"
            log "已禁用密码登录"
            ;;
        [nN])
            sed -i 's/^#\?PasswordAuthentication.*/PasswordAuthentication yes/' "$ssh_config"
            log "已启用密码登录"
            ;;
        *)
            log "保持原有密码登录设置"
            ;;
    esac
    
    # 更新 SSH 端口
    sed -i "s/^#\?Port.*/Port $new_port/" "$ssh_config"
    
    # 配置防火墙
    if command -v ufw &> /dev/null; then
        ufw allow "$new_port"/tcp
        ufw reload
    fi
    
    # 重启 SSH 服务
    systemctl restart sshd || error "重启 SSH 服务失败"
    log "${green}SSH 配置完成，新端口: $new_port${plain}"
}

# 增强版 Fail2Ban 配置
configure_fail2ban() {
    log "${yellow}正在配置 Fail2Ban...${plain}"
    
    # 安装 Fail2Ban
    if ! command -v fail2ban-server &> /dev/null; then
        apt update && apt install -y fail2ban || error "安装 Fail2Ban 失败"
    fi
    
    local config_file="/etc/fail2ban/jail.local"
    backup_config "$config_file"
    
    # 获取配置参数
    read -p "请输入最大尝试次数 [3]: " maxretry
    read -p "请输入封禁时间(秒) [86400]: " bantime
    read -p "请输入检测时间窗口(秒) [600]: " findtime
    
    maxretry=${maxretry:-3}
    bantime=${bantime:-86400}
    findtime=${findtime:-600}
    
    # 创建配置
    cat > "$config_file" <<EOF
[DEFAULT]
ignoreip = 127.0.0.1/8 ::1
bantime = $bantime
findtime = $findtime
maxretry = $maxretry
banaction = ufw

[sshd]
enabled = true
port = $(grep ^Port /etc/ssh/sshd_config | awk '{print $2}')
logpath = /var/log/auth.log
maxretry = $maxretry
EOF
    
    systemctl restart fail2ban || error "重启 Fail2Ban 失败"
    log "${green}Fail2Ban 配置完成${plain}"
}

# 优化版 DNS 配置
configure_dns() {
    log "${yellow}正在配置 DNS...${plain}"
    
    # 备份当前配置
    backup_config "/etc/resolv.conf"
    
    echo "可用的 DNS 配置:"
    echo "1) Google DNS (8.8.8.8, 8.8.4.4)"
    echo "2) Cloudflare DNS (1.1.1.1, 1.0.0.1)"
    echo "3) 阿里云 DNS (223.5.5.5, 223.6.6.6)"
    echo "4) 自定义 DNS"
    
    read -p "请选择 DNS [1]: " choice
    choice=${choice:-1}
    
    case "$choice" in
        1)
            dns1="8.8.8.8"
            dns2="8.8.4.4"
            ;;
        2)
            dns1="1.1.1.1"
            dns2="1.0.0.1"
            ;;
        3)
            dns1="223.5.5.5"
            dns2="223.6.6.6"
            ;;
        4)
            read -p "请输入首选 DNS: " dns1
            read -p "请输入备用 DNS: " dns2
            ;;
        *)
            error "无效选择"
            ;;
    esac
    
    # 配置 DNS
    cat > "/etc/resolv.conf" <<EOF
nameserver $dns1
nameserver $dns2
EOF
    
    # 测试 DNS
    if ! ping -c 1 google.com &> /dev/null; then
        log "${yellow}警告: DNS 可能配置错误，请检查网络连接${plain}"
    else
        log "${green}DNS 配置完成${plain}"
    fi
}

# 主菜单
show_menu() {
    echo -e "\n${green}==== 服务器安全加固工具 ====${plain}"
    echo "1) 修改 SSH 配置"
    echo "2) 配置 Fail2Ban"
    echo "3) 解封 IP"
    echo "4) 更新系统源"
    echo "5) 配置 DNS"
    echo "6) 系统时间同步"
    echo "7) 查看配置日志"
    echo "8) 退出"
    echo
    read -p "请选择 [1-8]: " choice
    
    case "$choice" in
        1) modify_ssh_config ;;
        2) configure_fail2ban ;;
        3) unban_ip ;;
        4) update_sources ;;
        5) configure_dns ;;
        6) enable_ntp_service ;;
        7) [[ -f "$LOG_FILE" ]] && cat "$LOG_FILE" || echo "暂无日志" ;;
        8) log "${green}感谢使用！${plain}"; exit 0 ;;
        *) log "${red}无效选择${plain}" ;;
    esac
}

# 主程序
main() {
    check_system
    init_system
    
    while true; do
        show_menu
    done
}

main "$@"
