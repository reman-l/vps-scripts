#!/bin/sh
set -e

[ "$(id -u)" -ne 0 ] && { echo "错误：请使用 root 权限执行！"; exit 1; }

# 卸载清理函数
do_uninstall() {
    echo -e "\n正在彻底卸载 sing-box 并清除所有相关数据与规则..."
    
    # 1. 停止并清理防火墙与 ipset
    [ -f /etc/sing-box/firewall.sh ] && /bin/sh /etc/sing-box/firewall.sh stop 2>/dev/null || true
    if command -v ipset >/dev/null 2>&1; then
        ipset flush china_ip 2>/dev/null || true
        ipset destroy china_ip 2>/dev/null || true
    fi

    # 2. 停止守护服务
    if command -v systemctl >/dev/null 2>&1; then
        systemctl stop sing-box 2>/dev/null || true
        systemctl disable sing-box 2>/dev/null || true
        rm -f /etc/systemd/system/sing-box.service
        systemctl daemon-reload 2>/dev/null || true
    elif command -v rc-service >/dev/null 2>&1; then
        rc-service sing-box stop 2>/dev/null || true
        rc-update del sing-box default 2>/dev/null || true
        rm -f /etc/init.d/sing-box
    fi

    # 3. 删除二进制核心与配置/日志/证书目录
    rm -f /usr/local/bin/sing-box /usr/local/bin/sb
    rm -rf /etc/sing-box /var/log/sing-box /run/sing-box.pid

    echo "=================================================="
    echo " 卸载完成！sing-box 服务、配置、证书与防火墙规则已彻底清理干净。"
    echo "=================================================="
    exit 0
}

echo "=================================================="
echo "  sing-box 智能多协议综合部署脚本 (Reality/Hy2/AnyTLS)"
echo "  安全特性: 地区自适应 | 双向防溯源 | 端口跳跃 | 彻底卸载"
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

echo " 完成！[检测到: ${REGION_NAME} \vert{} IP:${PUB_IP}]"
echo "--------------------------------------------------"

# 2. 选择操作菜单
echo "请选择操作模式 (输入编号，直接回车默认 1 2 3 全选安装):"
echo "  1) VLESS-Reality (TCP / 偷窥伪装)"
echo "  2) Hysteria 2    (UDP / 极速双边加速 / 支持端口跳跃)"
echo "  3) AnyTLS        (TCP / 抗封锁 TLS-in-TLS 混淆)"
echo "  0) 彻底卸载清理  (清理所有配置、服务、证书及防火墙规则)"
echo "--------------------------------------------------"
printf "请输入选项 [默认: 1 2 3 全部启用]: "
read -r CHOICE </dev/tty
[ -z "$CHOICE" ] && CHOICE="1 2 3"

case "$CHOICE" in *0*) do_uninstall ;; esac

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
    printf "是否启用 HY2 端口跳跃 (Port Hopping)？[Y/n，默认: Y]: "
    read -r INPUT_HOP </dev/tty
    case "$INPUT_HOP" in [nN][oO]|[nN]) ENABLE_PORT_HOP=0 ;; *) ENABLE_PORT_HOP=1 ;; esac

    if [ "$ENABLE_PORT_HOP" -eq 1 ]; then
        printf "请输入跳跃端口范围 (起始:结束) [默认: 20000:50000]: "
        read -r INPUT_HRANGE </dev/tty
        HOP_INPUT=${INPUT_HRANGE:-"20000:50000"}
        HOP_START=$(echo "$HOP_INPUT" | tr '-' ':' | cut -d':' -f1)
        HOP_END=$(echo "$HOP_INPUT" |
