#!/bin/sh
set -e

[ "$(id -u)" -ne 0 ] && { echo "错误：请使用 root 权限执行！"; exit 1; }

echo "=================================================="
echo "    sing-box 多协议集成一键部署 (Reality / Hy2 / AnyTLS)"
echo "=================================================="
echo "请选择要启用的协议 (输入编号，多个用空格隔开，直接回车全选):"
echo "  1) VLESS-Reality (TCP / 偷窥伪装)"
echo "  2) Hysteria 2    (UDP / 极速双边加速)"
echo "  3) AnyTLS        (TCP / 抗封锁 TLS-in-TLS 混淆)"
echo "--------------------------------------------------"
printf "请输入选项 [默认: 1 2 3 全部启用]: "
read -r CHOICE </dev/tty
[ -z "$CHOICE" ] && CHOICE="1 2 3"

ENABLE_REALITY=0
ENABLE_HY2=0
ENABLE_ANYTLS=0

case "$CHOICE" in *1*) ENABLE_REALITY=1 ;; esac
case "$CHOICE" in *2*) ENABLE_HY2=1 ;; esac
case "$CHOICE" in *3*) ENABLE_ANYTLS=1 ;; esac

[ "$ENABLE_REALITY" -eq 0 ] && [ "$ENABLE_HY2" -eq 0 ] && [ "$ENABLE_ANYTLS" -eq 0 ] && {
    echo "未识别到有效选择，已默认全选启用！"
    ENABLE_REALITY=1; ENABLE_HY2=1; ENABLE_ANYTLS=1
}

printf "\n请输入节点别名前缀 [默认: %s]: " "$(hostname)"
read -r INPUT_NAME </dev/tty
NODE_NAME=${INPUT_NAME:-$(hostname)}

if [ "$ENABLE_REALITY" -eq 1 ]; then
    printf "请输入 Reality 监听端口 [默认: 443]: "
    read -r R_PORT </dev/tty
    REALITY_PORT=${R_PORT:-443}
    printf "请输入 Reality 伪装域名 (SNI) [默认: www.apple.com]: "
    read -r R_SNI </dev/tty
    REALITY_SNI=${R_SNI:-www.apple.com}
fi

if [ "$ENABLE_HY2" -eq 1 ]; then
    printf "请输入 Hysteria 2 监听端口 [默认: 8443]: "
    read -r H_PORT </dev/tty
    HY2_PORT=${H_PORT:-8443}
    printf "请输入 Hysteria 2 伪装域名 [默认: apple.com]: "
    read -r H_SNI </dev/tty
    HY2_SNI=${H_SNI:-apple.com}
fi

if [ "$ENABLE_ANYTLS" -eq 1 ]; then
    printf "请输入 AnyTLS 监听端口 [默认: 2096]: "
    read -r A_PORT </dev/tty
    ANYTLS_PORT=${A_PORT:-2096}
    printf "请输入 AnyTLS 伪装域名 [默认: apple.com]: "
    read -r A_SNI </dev/tty
    ANYTLS_SNI=${A_SNI:-apple.com}

    if [ "$ENABLE_REALITY" -eq 1 ] && [ "$REALITY_PORT" = "$ANYTLS_PORT" ]; then
        ANYTLS_PORT=$((REALITY_PORT + 1))
        echo "提示: Reality 和 AnyTLS 同属 TCP 协议，已将 AnyTLS 端口自动顺延至: ${ANYTLS_PORT}"
    fi
fi

echo -e "\n[1/5] 安装底层依赖与运行库..."
if command -v apk >/dev/null 2>&1; then
    apk update && apk add curl tar gzip openssl gcompat libc6-compat
elif command -v apt-get >/dev/null 2>&1; then
    apt-get update -y && apt-get install -y curl tar gzip openssl
elif command -v yum >/dev/null 2>&1; then
    yum install -y curl tar gzip openssl
fi

echo "[2/5] 探测架构并部署 sing-box 最新核心..."
ARCH=$(uname -m)
case "$ARCH" in
    x86_64)          SBARCH="amd64" ;;
    aarch64|arm64)   SBARCH="arm64" ;;
    *) echo "错误: 不支持的 CPU 架构: $ARCH"; exit 1 ;;
esac

LATEST_TAG=$(curl -s https://api.github.com/repos/SagerNet/sing-box/releases/latest | grep -o '"tag_name": *"[^"]*"' | head -n1 | cut -d'"' -f4)
[ -z "$LATEST_TAG" ] && LATEST_TAG="v1.11.4"
VER="${LATEST_TAG#v}"

cd /tmp
curl -Lo sb.tar.gz "https://github.com/SagerNet/sing-box/releases/download/${LATEST_TAG}/sing-box-${VER}-linux-${SBARCH}.tar.gz"
tar -xzf sb.tar.gz
mv "sing-box-${VER}-linux-${SBARCH}/sing-box" /usr/local/bin/sing-box
chmod +x /usr/local/bin/sing-box
rm -rf sb.tar.gz "sing-box-${VER}-linux-${SBARCH}"
SB_BIN="/usr/local/bin/sing-box"

echo "[3/5] 动态生成加密凭据与安全证书..."
mkdir -p /etc/sing-box/cert /var/log/sing-box

if [ "$ENABLE_HY2" -eq 1 ] || [ "$ENABLE_ANYTLS" -eq 1 ]; then
    CERT_SNI="${HY2_SNI:-${ANYTLS_SNI:-apple.com}}"
    openssl ecparam -name prime256v1 -genkey -noout -out /etc/sing-box/cert/server.key 2>/dev/null
    openssl req -x509 -new -nodes -key /etc/sing-box/cert/server.key \
      -out /etc/sing-box/cert/server.crt \
      -days 3650 -subj "/CN=${CERT_SNI}" 2>/dev/null
    chmod 644 /etc/sing-box/cert/server.crt
    chmod 600 /etc/sing-box/cert/server.key
    CERT_PIN=$(openssl x509 -in /etc/sing-box/cert/server.crt -outform der | sha256sum | awk '{print $1}')
fi

INBOUNDS_BLOCK=""

append_inbound() {
    if [ -z "$INBOUNDS_BLOCK" ]; then
        INBOUNDS_BLOCK="$1"
    else
        INBOUNDS_BLOCK="${INBOUNDS_BLOCK},
$1"
    fi
}

if [ "$ENABLE_REALITY" -eq 1 ]; then
    REALITY_UUID=$($SB_BIN generate uuid)
    KEYPAIR=$($SB_BIN generate reality-keypair)
    REALITY_PRIKEY=$(echo "$KEYPAIR" | awk '/PrivateKey/{print $2}' | tr -d ' \r\n')
    REALITY_PUBKEY=$(echo "$KEYPAIR" | awk '/PublicKey/{print $2}' | tr -d ' \r\n')
    REALITY_SID=$($SB_BIN generate rand --hex 8)

    append_inbound "{
      \"type\": \"vless\",
      \"tag\": \"reality-in\",
      \"listen\": \"::\",
      \"listen_port\": ${REALITY_PORT},
      \"users\": [
        {
          \"name\": \"default\",
          \"uuid\": \"${REALITY_UUID}\",
          \"flow\": \"xtls-rprx-vision\"
        }
      ],
      \"tls\": {
        \"enabled\": true,
        \"server_name\": \"${REALITY_SNI}\",
        \"reality\": {
          \"enabled\": true,
          \"handshake\": {
            \"server\": \"${REALITY_SNI}\",
            \"server_port\": 443
          },
          \"private_key\": \"${REALITY_PRIKEY}\",
          \"short_id\": [
            \"${REALITY_SID}\"
          ]
        }
      }
    }"
fi

if [ "$ENABLE_HY2" -eq 1 ]; then
    HY2_PASS=$(openssl rand -hex 12)
    append_inbound "{
      \"type\": \"hysteria2\",
      \"tag\": \"hy2-in\",
      \"listen\": \"::\",
      \"listen_port\": ${HY2_PORT},
      \"users\": [
        {
          \"name\": \"default\",
          \"password\": \"${HY2_PASS}\"
        }
      ],
      \"tls\": {
        \"enabled\": true,
        \"certificate_path\": \"/etc/sing-box/cert/server.crt\",
        \"key_path\": \"/etc/sing-box/cert/server.key\"
      }
    }"
fi

if [ "$ENABLE_ANYTLS" -eq 1 ]; then
    ANYTLS_PASS=$(openssl rand -hex 12)
    append_inbound "{
      \"type\": \"anytls\",
      \"tag\": \"anytls-in\",
      \"listen\": \"::\",
      \"listen_port\": ${ANYTLS_PORT},
      \"users\": [
        {
          \"name\": \"default\",
          \"password\": \"${ANYTLS_PASS}\"
        }
      ],
      \"tls\": {
        \"enabled\": true,
        \"certificate_path\": \"/etc/sing-box/cert/server.crt\",
        \"key_path\": \"/etc/sing-box/cert/server.key\"
      }
    }"
fi

echo "[4/5] 写入 sing-box 配置文件..."
cat << EOF > /etc/sing-box/config.json
{
  "log": {
    "level": "warn",
    "timestamp": true
  },
  "inbounds": [
${INBOUNDS_BLOCK}
  ],
  "outbounds": [
    {
      \"type\": \"direct\",
      \"tag\": \"direct\"
    }
  ]
}
EOF

$SB_BIN check -c /etc/sing-box/config.json

echo "[5/5] 注册并启动系统服务..."
if command -v systemctl >/dev/null 2>&1; then
    cat << EOF > /etc/systemd/system/sing-box.service
[Unit]
Description=sing-box service
After=network.target nss-lookup.target

[Service]
ExecStart=${SB_BIN} run -c /etc/sing-box/config.json
Restart=on-failure
RestartSec=10s
LimitNOFILE=infinity

[Install]
WantedBy=multi-user.target
EOF
    systemctl daemon-reload
    systemctl enable --now sing-box
    systemctl restart sing-box
elif command -v rc-service >/dev/null 2>&1; then
    cat << 'EOF' > /etc/init.d/sing-box
#!/sbin/openrc-run
description="sing-box service"
command="/usr/local/bin/sing-box"
command_args="run -c /etc/sing-box/config.json"
command_background=true
pidfile="/run/sing-box.pid"

depend() {
    need net
    after firewall
}
EOF
    chmod +x /etc/init.d/sing-box
    rc-update add sing-box default 2>/dev/null || true
    rc-service sing-box restart
fi

sleep 1
PUB_IP=$(curl -s4 --connect-timeout 3 ifconfig.me || curl -s4 --connect-timeout 3 icanhazip.com || echo "SERVER_IP")

echo -e "\n======================= 部署成功 ======================="
echo "服务状态 : 正常运行中"
echo "服务器IP : ${PUB_IP}"
echo "--------------------------------------------------------"

if [ "$ENABLE_REALITY" -eq 1 ]; then
    echo "【VLESS-Reality 分享链接】:"
    echo "vless://${REALITY_UUID}@${PUB_IP}:${REALITY_PORT}?security=reality&encryption=none&pbk=${REALITY_PUBKEY}&headerType=none&type=tcp&flow=xtls-rprx-vision&sni=${REALITY_SNI}&sid=${REALITY_SID}&fp=chrome#${NODE_NAME}-Reality"
    echo ""
fi

if [ "$ENABLE_HY2" -eq 1 ]; then
    echo "【Hysteria 2 分享链接】:"
    echo "hysteria2://${HY2_PASS}@${PUB_IP}:${HY2_PORT}?sni=${HY2_SNI}&insecure=1&pinSHA256=${CERT_PIN}#${NODE_NAME}-HY2"
    echo ""
fi

if [ "$ENABLE_ANYTLS" -eq 1 ]; then
    echo "【AnyTLS 分享链接】:"
    echo "anytls://${ANYTLS_PASS}@${PUB_IP}:${ANYTLS_PORT}?sni=${ANYTLS_SNI}&insecure=1#${NODE_NAME}-AnyTLS"
    echo ""
fi

echo "--------------------------------------------------------"
echo "【OpenClash (Clash Meta) 静态配置块】:"
echo "proxies:"
if [ "$ENABLE_REALITY" -eq 1 ]; then
cat << EOF
  - name: ${NODE_NAME}-Reality
    type: vless
    server: ${PUB_IP}
    port: ${REALITY_PORT}
    uuid: ${REALITY_UUID}
    network: tcp
    udp: false
    tls: true
    flow: xtls-rprx-vision
    servername: ${REALITY_SNI}
    reality-opts:
      public-key: ${REALITY_PUBKEY}
      short-id: ${REALITY_SID}
    client-fingerprint: chrome
EOF
fi

if [ "$ENABLE_HY2" -eq 1 ]; then
cat << EOF
  - name: ${NODE_NAME}-HY2
    type: hysteria2
    server: ${PUB_IP}
    port: ${HY2_PORT}
    password: ${HY2_PASS}
    sni: ${HY2_SNI}
    skip-cert-verify: true
    fingerprint: ${CERT_PIN}
EOF
fi

if [ "$ENABLE_ANYTLS" -eq 1 ]; then
cat << EOF
  - name: ${NODE_NAME}-AnyTLS
    type: anytls
    server: ${PUB_IP}
    port: ${ANYTLS_PORT}
    password: ${ANYTLS_PASS}
    sni: ${ANYTLS_SNI}
    skip-cert-verify: true
EOF
fi
echo "========================================================"
