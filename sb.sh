#!/bin/sh
set -e

[ "$(id -u)" -ne 0 ] && { echo "错误：请使用 root 权限执行！"; exit 1; }

echo "=================================================="
echo "  sing-box 智能多协议综合部署脚本 (Reality/Hy2/AnyTLS)"
echo "  安全特性: 地区自适应 | 双向防溯源 (入站+出站双屏蔽) | WARP/SOCKS | HY2 端口跳跃"
echo "=================================================="

# 1. 探测公网 IP 与地理位置
printf "正在探测 VPS 所在地理位置..."
PUB_IP=$(curl -s4 --connect-timeout 3 ifconfig.me || curl -s4 --connect-timeout 3 icanhazip.com || echo "127.0.0.1")
COUNTRY_CODE=$(curl -s4 --connect-timeout 3 https://ipinfo.io/country 2>/dev/null || curl -s4 --connect-timeout 3 "http://ip-api.com/line?fields=countryCode" 2>/dev/null || echo "US")
COUNTRY_CODE=$(echo "$COUNTRY_CODE" | tr -d ' \r\n' | tr '[:lower:]' '[:upper:]')

case "$COUNTRY_CODE" in
    DE)
        REGION_NAME="🇩🇪 德国"
        DEF_REALITY_SNI="www.bmw.com"; DEF_HY2_SNI="bmw.de"; DEF_ANYTLS_SNI="bmw.de"
        ;;
    US)
        REGION_NAME="🇺🇸 美国"
        DEF_REALITY_SNI="www.cisco.com"; DEF_HY2_SNI="apple.com"; DEF_ANYTLS_SNI="apple.com"
        ;;
    JP)
        REGION_NAME="🇯🇵 日本"
        DEF_REALITY_SNI="www.sony.com"; DEF_HY2_SNI="sony.co.jp"; DEF_ANYTLS_SNI="sony.co.jp"
        ;;
    KR)
        REGION_NAME="🇰🇷 韩国"
        DEF_REALITY_SNI="www.samsung.com"; DEF_HY2_SNI="samsung.com"; DEF_ANYTLS_SNI="samsung.com"
        ;;
    HK)
        REGION_NAME="🇭🇰 香港"
        DEF_REALITY_SNI="www.hkex.com.hk"; DEF_HY2_SNI="hkex.com.hk"; DEF_ANYTLS_SNI="hkex.com.hk"
        ;;
    TW)
        REGION_NAME="🇹🇼 台湾"
        DEF_REALITY_SNI="www.asus.com"; DEF_HY2_SNI="asus.com"; DEF_ANYTLS_SNI="asus.com"
        ;;
    SG)
        REGION_NAME="🇸🇬 新加坡"
        DEF_REALITY_SNI="www.gov.sg"; DEF_HY2_SNI="gov.sg"; DEF_ANYTLS_SNI="gov.sg"
        ;;
    MX)
        REGION_NAME="🇲🇽 墨西哥"
        DEF_REALITY_SNI="www.mercadolibre.com.mx"; DEF_HY2_SNI="mercadolibre.com.mx"; DEF_ANYTLS_SNI="mercadolibre.com.mx"
        ;;
    *)
        REGION_NAME="🌐 节点"
        DEF_REALITY_SNI="www.apple.com"; DEF_HY2_SNI="apple.com"; DEF_ANYTLS_SNI="apple.com"
        ;;
esac

echo " 完成！[检测到: ${REGION_NAME} | IP: ${PUB_IP}]"
echo "--------------------------------------------------"

# 2. 选择协议
echo "请选择要启用的协议 (输入编号，多个用空格隔开，直接回车全选):"
echo "  1) VLESS-Reality (TCP / 偷窥伪装)"
echo "  2) Hysteria 2    (UDP / 极速双边加速 / 支持端口跳跃)"
echo "  3) AnyTLS        (TCP / 抗封锁 TLS-in-TLS 混淆)"
echo "--------------------------------------------------"
printf "请输入选项 [默认: 1 2 3 全部启用]: "
read -r CHOICE </dev/tty
[ -z "$CHOICE" ] && CHOICE="1 2 3"

ENABLE_REALITY=0; ENABLE_HY2=0; ENABLE_ANYTLS=0
case "$CHOICE" in *1*) ENABLE_REALITY=1 ;; esac
case "$CHOICE" in *2*) ENABLE_HY2=1 ;; esac
case "$CHOICE" in *3*) ENABLE_ANYTLS=1 ;; esac

[ "$ENABLE_REALITY" -eq 0 ] && [ "$ENABLE_HY2" -eq 0 ] && [ "$ENABLE_ANYTLS" -eq 0 ] && {
    echo "未识别到有效选择，已默认全选启用！"
    ENABLE_REALITY=1; ENABLE_HY2=1; ENABLE_ANYTLS=1
}

# 3. 入站屏蔽 (防 GFW 探测)
echo "--------------------------------------------------"
echo "【功能 1: 入站防护设置 (防嗅探扫描)】"
echo "⚠️  注意: 屏蔽中国 IP 入站仅限【通过中转机/专线/Realm/CDN】连接本 VPS 时开启！"
echo "⚠️  若国内客户端【直接连接】本 VPS，开启会导致你自己也被丢包阻断！"
printf "是否开启入站屏蔽中国 IP？[y/N，默认: N]: "
read -r INPUT_BLOCK_CN </dev/tty
ENABLE_BLOCK_CN=0
case "$INPUT_BLOCK_CN" in [yY][eE][sS]|[yY]) ENABLE_BLOCK_CN=1 ;; esac

# 4. 出站屏蔽 (防分流错误导致 VPN 溯源)
echo "--------------------------------------------------"
echo "【功能 2: 出站防溯源设置 (防 VPN 溯源)】"
echo "提示: 出站直接拒绝国内 IP、.cn 域名与常见国内站点，同时阻断私网内网。"
echo "作用: 即使客户端误开全局或分流规则失效，国内请求也会在 VPS 处直接被拒绝，"
echo "      绝对不会向国内目标发起连接，彻底避免国内日志记录 VPS IP 并被关联溯源。"
printf "是否开启出站屏蔽中国大陆 (IP & 域名)？[Y/n，默认: Y]: "
read -r INPUT_BLOCK_OUT_CN </dev/tty
ENABLE_BLOCK_OUT_CN=1
case "$INPUT_BLOCK_OUT_CN" in [nN][oO]|[nN]) ENABLE_BLOCK_OUT_CN=0 ;; esac

# 5. 出站套 WARP / SOCKS5 设置
echo "--------------------------------------------------"
echo "【功能 3: 出站分流模式】"
echo "  1) VPS 原生直连出站 (Direct，默认)"
echo "  2) 套用 WARP 本地 SOCKS5 (默认 127.0.0.1:40000，解锁流媒体/防人机验证)"
echo "  3) 套用自定义外部 SOCKS5 代理 (落地 IP / 端口 / 密码)"
printf "请选择出站模式 [默认: 1]: "
read -r INPUT_OUT_MODE </dev/tty
OUT_MODE=${INPUT_OUT_MODE:-1}

SOCKS_SERVER="127.0.0.1"
SOCKS_PORT=40000
SOCKS_USER=""
SOCKS_PASS=""

if [ "$OUT_MODE" = "2" ]; then
    printf "请输入 WARP SOCKS5 监听端口 [默认: 40000]: "
    read -r W_PORT </dev/tty
    SOCKS_PORT=${W_PORT:-40000}
elif [ "$OUT_MODE" = "3" ]; then
    printf "请输入 SOCKS5 服务器 IP/域名 [默认: 127.0.0.1]: "
    read -r S_SRV </dev/tty
    SOCKS_SERVER=${S_SRV:-"127.0.0.1"}
    printf "请输入 SOCKS5 端口 [默认: 1080]: "
    read -r S_PORT </dev/tty
    SOCKS_PORT=${S_PORT:-1080}
    printf "请输入 SOCKS5 用户名 (无则直接回车): "
    read -r SOCKS_USER </dev/tty
    printf "请输入 SOCKS5 密码 (无则直接回车): "
    read -r SOCKS_PASS </dev/tty
fi

# 6. 节点参数交互
printf "\n请输入节点别名前缀 [默认: %s]: " "${REGION_NAME}"
read -r INPUT_NAME </dev/tty
NODE_NAME=${INPUT_NAME:-"${REGION_NAME}"}

TCP_PORTS=""
UDP_PORTS=""

if [ "$ENABLE_REALITY" -eq 1 ]; then
    printf "请输入 Reality 监听端口 [默认: 443]: "
    read -r R_PORT </dev/tty
    REALITY_PORT=${R_PORT:-443}
    printf "请输入 Reality 伪装域名 [默认推荐: %s]: " "${DEF_REALITY_SNI}"
    read -r R_SNI </dev/tty
    REALITY_SNI=${R_SNI:-${DEF_REALITY_SNI}}
    TCP_PORTS="${REALITY_PORT}"
fi

ENABLE_PORT_HOP=0
HOP_PORT_RANGE="20000:50000"
HOP_DISPLAY="20000-50000"

if [ "$ENABLE_HY2" -eq 1 ]; then
    printf "请输入 Hysteria 2 监听端口 [默认: 8443]: "
    read -r H_PORT </dev/tty
    HY2_PORT=${H_PORT:-8443}
    printf "请输入 Hysteria 2 伪装域名 [默认推荐: %s]: " "${DEF_HY2_SNI}"
    read -r H_SNI </dev/tty
    HY2_SNI=${H_SNI:-${DEF_HY2_SNI}}
    UDP_PORTS="${HY2_PORT}"

    echo "--------------------------------------------------"
    echo "【功能 4: HY2 端口跳跃设置】"
    echo "提示: 端口跳跃可随机更换端口连接，对抗运营商对单个 UDP 端口的限速与阻断。"
    printf "是否启用 HY2 端口跳跃 (Port Hopping)？[Y/n，默认: Y]: "
    read -r INPUT_HOP </dev/tty
    case "$INPUT_HOP" in [nN][oO]|[nN]) ENABLE_PORT_HOP=0 ;; *) ENABLE_PORT_HOP=1 ;; esac

    if [ "$ENABLE_PORT_HOP" -eq 1 ]; then
        printf "请输入跳跃端口范围 (起始:结束) [默认: 20000:50000]: "
        read -r INPUT_HRANGE </dev/tty
        HOP_INPUT=${INPUT_HRANGE:-"20000:50000"}
        HOP_START=$(echo "$HOP_INPUT" | tr '-' ':' | cut -d':' -f1)
        HOP_END=$(echo "$HOP_INPUT" | tr '-' ':' | cut -d':' -f2)
        HOP_PORT_RANGE="${HOP_START}:${HOP_END}"
        HOP_DISPLAY="${HOP_START}-${HOP_END}"
    fi
fi

if [ "$ENABLE_ANYTLS" -eq 1 ]; then
    printf "请输入 AnyTLS 监听端口 [默认: 2096]: "
    read -r A_PORT </dev/tty
    ANYTLS_PORT=${A_PORT:-2096}
    printf "请输入 AnyTLS 伪装域名 [默认推荐: %s]: " "${DEF_ANYTLS_SNI}"
    read -r A_SNI </dev/tty
    ANYTLS_SNI=${A_SNI:-${DEF_ANYTLS_SNI}}

    if [ "$ENABLE_REALITY" -eq 1 ] && [ "$REALITY_PORT" = "$ANYTLS_PORT" ]; then
        ANYTLS_PORT=$((REALITY_PORT + 1))
        echo "提示: Reality 和 AnyTLS 同属 TCP 协议，已将 AnyTLS 端口自动顺延至: ${ANYTLS_PORT}"
    fi

    if [ -z "$TCP_PORTS" ]; then
        TCP_PORTS="${ANYTLS_PORT}"
    else
        TCP_PORTS="${TCP_PORTS},${ANYTLS_PORT}"
    fi
fi

echo -e "\n[1/5] 安装底层依赖与环境支持..."
if command -v apk >/dev/null 2>&1; then
    apk update && apk add curl tar gzip openssl iptables ip6tables ipset gcompat libc6-compat
elif command -v apt-get >/dev/null 2>&1; then
    apt-get update -y && apt-get install -y curl tar gzip openssl iptables ipset
elif command -v yum >/dev/null 2>&1; then
    yum install -y curl tar gzip openssl iptables ipset
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

echo "[3/5] 生成加密凭据与安全证书..."
mkdir -p /etc/sing-box/cert /etc/sing-box/rule-set /var/log/sing-box

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

OUTBOUNDS_BLOCK=""
if [ "$OUT_MODE" = "1" ]; then
    OUTBOUNDS_BLOCK='    {
      "type": "direct",
      "tag": "direct"
    }'
else
    AUTH_JSON=""
    if [ -n "$SOCKS_USER" ] && [ -n "$SOCKS_PASS" ]; then
        AUTH_JSON=",
      \"username\": \"${SOCKS_USER}\",
      \"password\": \"${SOCKS_PASS}\""
    fi
    OUTBOUNDS_BLOCK="    {
      \"type\": \"socks\",
      \"tag\": \"socks-out\",
      \"server\": \"${SOCKS_SERVER}\",
      \"server_port\": ${SOCKS_PORT},
      \"version\": \"5\"${AUTH_JSON}
    },
    {
      \"type\": \"direct\",
      \"tag\": \"direct\"
    }"
fi

# 出站防溯源规则生成 (下载 SRS 规则库)
ROUTE_BLOCK=""
if [ "$ENABLE_BLOCK_OUT_CN" -eq 1 ]; then
    echo "正在下载 GeoIP / GeoSite 大陆规则库以启用出站防溯源..."
    curl -fsSL "https://raw.githubusercontent.com/SagerNet/sing-geoip/rule-set/geoip-cn.srs" -o /etc/sing-box/rule-set/geoip-cn.srs 2>/dev/null || \
    curl -fsSL "https://cdn.jsdelivr.net/gh/SagerNet/sing-geoip@rule-set/geoip-cn.srs" -o /etc/sing-box/rule-set/geoip-cn.srs 2>/dev/null || true

    curl -fsSL "https://raw.githubusercontent.com/SagerNet/sing-geosite/rule-set/geosite-cn.srs" -o /etc/sing-box/rule-set/geosite-cn.srs 2>/dev/null || \
    curl -fsSL "https://cdn.jsdelivr.net/gh/SagerNet/sing-geosite@rule-set/geosite-cn.srs" -o /etc/sing-box/rule-set/geosite-cn.srs 2>/dev/null || true

    if [ -s /etc/sing-box/rule-set/geoip-cn.srs ] && [ -s /etc/sing-box/rule-set/geosite-cn.srs ]; then
        RULESET_JSON='    "rule_set": [
      {
        "tag": "geoip-cn",
        "type": "local",
        "format": "binary",
        "path": "/etc/sing-box/rule-set/geoip-cn.srs"
      },
      {
        "tag": "geosite-cn",
        "type": "local",
        "format": "binary",
        "path": "/etc/sing-box/rule-set/geosite-cn.srs"
      }
    ],'
    else
        RULESET_JSON='    "rule_set": [
      {
        "tag": "geoip-cn",
        "type": "remote",
        "format": "binary",
        "url": "https://raw.githubusercontent.com/SagerNet/sing-geoip/rule-set/geoip-cn.srs",
        "download_detour": "direct"
      },
      {
        "tag": "geosite-cn",
        "type": "remote",
        "format": "binary",
        "url": "https://raw.githubusercontent.com/SagerNet/sing-geosite/rule-set/geosite-cn.srs",
        "download_detour": "direct"
      }
    ],'
    fi

    ROUTE_BLOCK=",
  \"route\": {
${RULESET_JSON}
    \"rules\": [
      {
        \"action\": \"reject\",
        \"rule_set\": [
          \"geoip-cn\",
          \"geosite-cn\"
        ]
      },
      {
        \"action\": \"reject\",
        \"ip_is_private\": true
      }
    ]
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
${OUTBOUNDS_BLOCK}
  ]${ROUTE_BLOCK}
}
EOF

$SB_BIN check -c /etc/sing-box/config.json

# 5. 配置防火墙脚本 (管理 端口跳跃 与 入站屏蔽中国IP)
if [ "$ENABLE_BLOCK_CN" -eq 1 ]; then
    echo "正在拉取中国大陆 IP CIDR 网段库以启用入站屏蔽..."
    curl -sSL "https://raw.githubusercontent.com/mayaxcn/china-ip-list/master/chnroute.txt" -o /etc/sing-box/cn.zone || \
    curl -sSL "https://ispip.clang.cn/all_cn.txt" -o /etc/sing-box/cn.zone || true
fi

cat << 'EOF' > /etc/sing-box/firewall.sh
#!/bin/sh
action="$1"

ENABLE_BLOCK_CN=__BLOCK_CN__
ENABLE_PORT_HOP=__PORT_HOP__
HY2_PORT=__HY2_PORT__
HOP_PORT_RANGE="__HOP_PORT_RANGE__"
TCP_PORTS="__TCP_PORTS__"
UDP_PORTS="__UDP_PORTS__"

case "$action" in
  start)
    if [ "$ENABLE_PORT_HOP" -eq 1 ]; then
      iptables -t nat -C PREROUTING -p udp --dport "$HOP_PORT_RANGE" -j REDIRECT --to-ports "$HY2_PORT" 2>/dev/null || \
      iptables -t nat -A PREROUTING -p udp --dport "$HOP_PORT_RANGE" -j REDIRECT --to-ports "$HY2_PORT"

      iptables -C INPUT -p udp --dport "$HOP_PORT_RANGE" -j ACCEPT 2>/dev/null || \
      iptables -I INPUT -p udp --dport "$HOP_PORT_RANGE" -j ACCEPT

      ip6tables -t nat -C PREROUTING -p udp --dport "$HOP_PORT_RANGE" -j REDIRECT --to-ports "$HY2_PORT" 2>/dev/null || \
      ip6tables -t nat -A PREROUTING -p udp --dport "$HOP_PORT_RANGE" -j REDIRECT --to-ports "$HY2_PORT" 2>/dev/null || true

      ip6tables -C INPUT -p udp --dport "$HOP_PORT_RANGE" -j ACCEPT 2>/dev/null || \
      ip6tables -I INPUT -p udp --dport "$HOP_PORT_RANGE" -j ACCEPT 2>/dev/null || true
    fi

    if [ "$ENABLE_BLOCK_CN" -eq 1 ] && [ -f /etc/sing-box/cn.zone ]; then
      if command -v ipset >/dev/null 2>&1; then
        ipset create china_ip hash:net family inet maxelem 65536 2>/dev/null || true
        ipset flush china_ip 2>/dev/null || true
        sed 's/^/add china_ip /' /etc/sing-box/cn.zone | ipset restore -! 2>/dev/null || true

        if [ -n "$TCP_PORTS" ]; then
          iptables -C INPUT -p tcp -m multiport --dports "$TCP_PORTS" -m set --match-set china_ip src -j DROP 2>/dev/null || \
          iptables -I INPUT -p tcp -m multiport --dports "$TCP_PORTS" -m set --match-set china_ip src -j DROP
        fi

        if [ -n "$UDP_PORTS" ]; then
          iptables -C INPUT -p udp -m multiport --dports "$UDP_PORTS" -m set --match-set china_ip src -j DROP 2>/dev/null || \
          iptables -I INPUT -p udp -m multiport --dports "$UDP_PORTS" -m set --match-set china_ip src -j DROP
        fi

        if [ "$ENABLE_PORT_HOP" -eq 1 ]; then
          iptables -C INPUT -p udp --dport "$HOP_PORT_RANGE" -m set --match-set china_ip src -j DROP 2>/dev/null || \
          iptables -I INPUT -p udp --dport "$HOP_PORT_RANGE" -m set --match-set china_ip src -j DROP
        fi
      fi
    fi
    ;;

  stop)
    if [ "$ENABLE_PORT_HOP" -eq 1 ]; then
      iptables -t nat -D PREROUTING -p udp --dport "$HOP_PORT_RANGE" -j REDIRECT --to-ports "$HY2_PORT" 2>/dev/null || true
      iptables -D INPUT -p udp --dport "$HOP_PORT_RANGE" -j ACCEPT 2>/dev/null || true
      ip6tables -t nat -D PREROUTING -p udp --dport "$HOP_PORT_RANGE" -j REDIRECT --to-ports "$HY2_PORT" 2>/dev/null || true
      ip6tables -D INPUT -p udp --dport "$HOP_PORT_RANGE" -j ACCEPT 2>/dev/null || true
    fi

    if [ "$ENABLE_BLOCK_CN" -eq 1 ]; then
      [ -n "$TCP_PORTS" ] && iptables -D INPUT -p tcp -m multiport --dports "$TCP_PORTS" -m set --match-set china_ip src -j DROP 2>/dev/null || true
      [ -n "$UDP_PORTS" ] && iptables -D INPUT -p udp -m multiport --dports "$UDP_PORTS" -m set --match-set china_ip src -j DROP 2>/dev/null || true
      if [ "$ENABLE_PORT_HOP" -eq 1 ]; then
        iptables -D INPUT -p udp --dport "$HOP_PORT_RANGE" -m set --match-set china_ip src -j DROP 2>/dev/null || true
      fi
    fi
    ;;
esac
EOF

sed -i "s/__BLOCK_CN__/${ENABLE_BLOCK_CN}/g" /etc/sing-box/firewall.sh
sed -i "s/__PORT_HOP__/${ENABLE_PORT_HOP}/g" /etc/sing-box/firewall.sh
sed -i "s/__HY2_PORT__/${HY2_PORT:-8443}/g" /etc/sing-box/firewall.sh
sed -i "s/__HOP_PORT_RANGE__/${HOP_PORT_RANGE}/g" /etc/sing-box/firewall.sh
sed -i "s/__TCP_PORTS__/${TCP_PORTS}/g" /etc/sing-box/firewall.sh
sed -i "s/__UDP_PORTS__/${UDP_PORTS}/g" /etc/sing-box/firewall.sh
chmod +x /etc/sing-box/firewall.sh

echo "[5/5] 注册并启动系统服务..."
if command -v systemctl >/dev/null 2>&1; then
    cat << EOF > /etc/systemd/system/sing-box.service
[Unit]
Description=sing-box service
After=network.target nss-lookup.target

[Service]
ExecStartPre=/bin/sh /etc/sing-box/firewall.sh start
ExecStart=${SB_BIN} run -c /etc/sing-box/config.json
ExecStopPost=/bin/sh /etc/sing-box/firewall.sh stop
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

start_pre() {
    /bin/sh /etc/sing-box/firewall.sh start
}

stop_post() {
    /bin/sh /etc/sing-box/firewall.sh stop
}

depend() {
    need net
    after firewall
}
EOF
    chmod +x /etc/init.d/sing-box
    rc-update add sing-box default 2>/dev/null || true
    rc-service sing-box restart
fi

/bin/sh /etc/sing-box/firewall.sh start 2>/dev/null || true
sleep 1

echo -e "\n======================= 部署成功 ======================="
echo "服务状态 : 正常运行中"
echo "服务器IP : ${PUB_IP} (${REGION_NAME})"
if [ "$ENABLE_BLOCK_CN" -eq 1 ]; then
    echo "入站防护 : [已开启] 屏蔽中国大陆 IP 探测扫描 (DROP 丢包)"
else
    echo "入站防护 : [未开启] 放行全部 IP 入站"
fi

if [ "$ENABLE_BLOCK_OUT_CN" -eq 1 ]; then
    echo "出站防溯源: [已开启] 屏蔽中国大陆 (IP & 域名) 与内网私网 (REJECT 拒绝)"
else
    echo "出站防溯源: [未开启] 允许直连任何目标"
fi

if [ "$OUT_MODE" = "1" ]; then
    echo "出站模式 : VPS 原生直连出站 (Direct)"
elif [ "$OUT_MODE" = "2" ]; then
    echo "出站模式 : 链式转发 WARP 本地 SOCKS5 (127.0.0.1:${SOCKS_PORT})"
else
    echo "出站模式 : 链式转发自定义 SOCKS5 (${SOCKS_SERVER}:${SOCKS_PORT})"
fi

if [ "$ENABLE_HY2" -eq 1 ] && [ "$ENABLE_PORT_HOP" -eq 1 ]; then
    echo "HY2 状态 : 监听端口 ${HY2_PORT} | 端口跳跃范围 [${HOP_DISPLAY}]"
fi
echo "--------------------------------------------------------"

if [ "$ENABLE_REALITY" -eq 1 ]; then
    echo "【VLESS-Reality 分享链接】:"
    echo "vless://${REALITY_UUID}@${PUB_IP}:${REALITY_PORT}?security=reality&encryption=none&pbk=${REALITY_PUBKEY}&headerType=none&type=tcp&flow=xtls-rprx-vision&sni=${REALITY_SNI}&sid=${REALITY_SID}&fp=chrome#${NODE_NAME}-Reality"
    echo ""
fi

if [ "$ENABLE_HY2" -eq 1 ]; then
    echo "【Hysteria 2 分享链接】:"
    if [ "$ENABLE_PORT_HOP" -eq 1 ]; then
        echo "hysteria2://${HY2_PASS}@${PUB_IP}:${HY2_PORT}?sni=${HY2_SNI}&insecure=1&pinSHA256=${CERT_PIN}&mport=${HOP_DISPLAY}#${NODE_NAME}-HY2"
    else
        echo "hysteria2://${HY2_PASS}@${PUB_IP}:${HY2_PORT}?sni=${HY2_SNI}&insecure=1&pinSHA256=${CERT_PIN}#${NODE_NAME}-HY2"
    fi
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
  if [ "$ENABLE_PORT_HOP" -eq 1 ]; then
cat << EOF
  - name: ${NODE_NAME}-HY2
    type: hysteria2
    server: ${PUB_IP}
    port: ${HY2_PORT}
    ports: ${HOP_DISPLAY}
    hop-interval: 30
    password: ${HY2_PASS}
    sni: ${HY2_SNI}
    skip-cert-verify: true
    fingerprint: ${CERT_PIN}
EOF
  else
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
