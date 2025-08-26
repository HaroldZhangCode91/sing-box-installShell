#!/bin/bash
# 修正版 Sing-Box Server 一键安装脚本
# 完全修复文件名格式，版本号不含v前缀，支持Ubuntu/Debian/CentOS

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
        apt install -y wget curl tar
    elif [[ $OS == *"CentOS"* || $OS == *"RedHat"* ]]; then
        yum install -y wget curl tar
    else
        echo "不支持的操作系统"
        exit 1
    fi
}

# 下载并安装Sing-Box
install_singbox() {
    echo "正在安装Sing-Box..."
    
    # 获取最新版本标签（包含v前缀，如v1.12.3）
    LATEST_TAG=$(curl -s https://api.github.com/repos/SagerNet/sing-box/releases/latest | grep -oP '"tag_name": "\K(.*)(?=")')
    if [ -z "$LATEST_TAG" ]; then
        echo "获取最新版本失败，请检查网络连接"
        exit 1
    fi
    
    # 去除版本号中的v前缀（如v1.12.3 → 1.12.3，用于文件名）
    LATEST_VERSION=${LATEST_TAG#v}
    
    # 根据系统架构确定下载文件名
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
    
    # 构建正确的下载链接（文件名中版本号不含v前缀）
    DOWNLOAD_URL="https://github.com/SagerNet/sing-box/releases/download/${LATEST_TAG}/sing-box-${LATEST_VERSION}-linux-${ARCH}.tar.gz"
    
    # 显示下载链接用于调试
    echo "下载地址: $DOWNLOAD_URL"
    
    # 下载安装包
    if ! wget -O /tmp/sing-box.tar.gz "$DOWNLOAD_URL"; then
        echo "下载失败，请检查网络或版本是否存在"
        exit 1
    fi
    
    # 解压并安装
    mkdir -p /tmp/sing-box
    tar -zxf /tmp/sing-box.tar.gz -C /tmp/sing-box --strip-components=1
    
    # 验证解压结果
    if [ ! -f "/tmp/sing-box/sing-box" ]; then
        echo "解压失败，未找到可执行文件"
        exit 1
    fi
    
    # 移动二进制文件
    mv /tmp/sing-box/sing-box /usr/local/bin/
    chmod +x /usr/local/bin/sing-box
    
    # 创建配置目录
    mkdir -p /etc/sing-box
    
    # 清理临时文件
    rm -rf /tmp/sing-box.tar.gz /tmp/sing-box
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
    "level": "warning",
    "timestamp": true
  },
  "inbounds": [
    {
      "type": "shadowsocks",
      "listen": "0.0.0.0",
      "listen_port": $PORT,
      "password": "$PASSWORD",
      "method": "$METHOD",
      "udp": true,
      "tcp_fast_open": true
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
