#!/bin/bash
# Sing-Box Server 一键安装脚本
# 支持 Ubuntu/Debian/CentOS 系统

# 检查是否为root用户
if [ "$(id -u)" -ne 0 ]; then
    echo "请使用root用户运行此脚本 (sudo -i)"
    exit 1
fi

# 检查系统类型
check_system() {
    if [ -f /etc/os-release ]; then
        . /etc/os-release
        OS=$NAME
        VER=$VERSION_ID
    else
        echo "不支持的操作系统"
        exit 1
    fi
}

# 安装依赖
install_dependencies() {
    echo "正在安装依赖..."
    if [[ $OS == *"Ubuntu"* || $OS == *"Debian"* ]]; then
        apt update -y
        apt install -y wget curl unzip
    elif [[ $OS == *"CentOS"* || $OS == *"RedHat"* ]]; then
        yum install -y wget curl unzip
    else
        echo "不支持的操作系统"
        exit 1
    fi
}

# 下载并安装Sing-Box
install_singbox() {
    echo "正在安装Sing-Box..."
    
    # 获取最新版本
    LATEST_VERSION=$(curl -s https://api.github.com/repos/SagerNet/sing-box/releases/latest | grep -oP '"tag_name": "\K(.*)(?=")')
    
    # 根据系统架构下载
    ARCH=$(uname -m)
    case $ARCH in
        x86_64)
            ARCH="amd64"
            ;;
        aarch64)
            ARCH="arm64"
            ;;
        *)
            echo "不支持的架构: $ARCH"
            exit 1
            ;;
    esac
    
    # 下载安装包
    wget -O /tmp/sing-box.zip "https://github.com/SagerNet/sing-box/releases/download/$LATEST_VERSION/sing-box-$LATEST_VERSION-linux-$ARCH.zip"
    
    # 解压并安装
    unzip -q /tmp/sing-box.zip -d /tmp
    mv /tmp/sing-box-$LATEST_VERSION-linux-$ARCH/sing-box /usr/local/bin/
    chmod +x /usr/local/bin/sing-box
    
    # 创建配置目录
    mkdir -p /etc/sing-box
}

# 生成配置文件
generate_config() {
    echo "正在生成配置文件..."
    
    # 随机端口(10000-65535)
    PORT=$((RANDOM % 55535 + 10000))
    
    # 随机密码
    PASSWORD=$(head -c 16 /dev/urandom | base64)
    
    # 随机加密方式
    METHODS=("aes-256-gcm" "chacha20-ietf-poly1305" "xchacha20-ietf-poly1305")
    METHOD=${METHODS[$RANDOM % ${#METHODS[@]}]}
    
    # 创建配置文件
    cat > /etc/sing-box/config.json << EOF
{
  "log": {
    "level": "info",
    "timestamp": true
  },
  "inbounds": [
    {
      "type": "shadowsocks",
      "listen": "0.0.0.0",
      "port": $PORT,
      "password": "$PASSWORD",
      "method": "$METHOD",
      "udp": true
    }
  ],
  "outbounds": [
    {
      "type": "direct"
    }
  ]
}
EOF

    echo "配置信息如下(请保存)："
    echo "服务器IP: $(curl -s icanhazip.com)"
    echo "端口: $PORT"
    echo "密码: $PASSWORD"
    echo "加密方式: $METHOD"
    echo "协议: shadowsocks"
}

# 设置系统服务
setup_service() {
    echo "正在设置系统服务..."
    
    cat > /etc/systemd/system/sing-box.service << EOF
[Unit]
Description=Sing-Box Service
After=network.target

[Service]
Type=simple
ExecStart=/usr/local/bin/sing-box run -c /etc/sing-box/config.json
Restart=always
User=root

[Install]
WantedBy=multi-user.target
EOF

    # 启动服务
    systemctl daemon-reload
    systemctl start sing-box
    systemctl enable sing-box
    
    echo "Sing-Box 服务已启动"
}

# 开放防火墙端口
open_firewall() {
    echo "正在配置防火墙..."
    if command -v ufw &> /dev/null; then
        ufw allow $PORT/tcp
        ufw allow $PORT/udp
        ufw reload
    elif command -v firewall-cmd &> /dev/null; then
        firewall-cmd --zone=public --add-port=$PORT/tcp --permanent
        firewall-cmd --zone=public --add-port=$PORT/udp --permanent
        firewall-cmd --reload
    fi
}

# 主流程
main() {
    check_system
    install_dependencies
    install_singbox
    generate_config
    open_firewall
    setup_service
    echo "Sing-Box Server 安装完成！"
}

main
