# sing-box 多协议智能自适应一键部署脚本

基于官方最新核心构建的高性能、轻量级代理服务一体化脚本。支持 **VLESS-Reality**、**Hysteria 2** 与 **AnyTLS** 任意组合部署，内置**地理位置智能识别**、**双向防溯源（入站防嗅探 + 出站防关联）**、**HY2 端口跳跃**、**WARP / SOCKS5 链式代理**以及**一键彻底卸载清理**。

---

## 核心特性

- **多协议自由组合**：交互式选择单一协议、双协议或三协议共存（直接回车即默认全选）。
- **智能地区探测与伪装匹配**：
  - 自动识别 VPS 地理位置（🇩🇪 德国、🇺🇸 美国、🇯🇵 日本、🇰🇷 韩国、🇭🇰 香港、🇹🇼 台湾、🇸🇬 新加坡、🇲🇽 墨西哥等）。
  - 自动匹配当地支持 TLS 1.3 的顶级本土伪装域名（如 BMW、Sony、Samsung、HKEX、Asus 等），生成纯净的带国旗 Emoji 节点别名。
- **全方位双向防溯源**：
  - **出站防关联（默认开启）**：sing-box 路由层原生阻断大陆 IP（`geoip-cn`）、大陆域名（`geosite-cn`）与私网内网（`ip_is_private`）。杜绝因客户端误开全局或分流规则失效导致 VPS 访问境内目标，避免 VPS IP 被境内应用日志记录并关联溯源。
  - **入站防探测（按需开启）**：基于 `ipset` 在内核网络层针对代理端口直接丢弃（`DROP`）大陆 IP 访问，让 GFW 主动嗅探扫描完全超时（安全隔离，绝不影响 22 端口 SSH；适合中转/专线/Realm/CDN 落地场景）。
- **Hysteria 2 端口跳跃（Port Hopping）**：
  - 支持自定义 UDP 跳跃区间（默认 `20000:50000`），对抗运营商对单个 UDP 端口的 QoS 限速与阻断。
  - 防火墙规则与系统守护服务生命周期深度绑定，启停自愈，不留任何残留脏规则。
- **出站链式转发**：原生支持切换为本地 WARP SOCKS5（默认 `127.0.0.1:40000`）或外部落地 SOCKS5 代理，实现流媒体解锁与防 Cloudflare 人机验证。
- **一键彻底卸载清理**：一键彻底清除 sing-box 核心程序、所有配置文件、自签证书、系统服务守护以及防火墙/ipset 规则，不留系统垃圾。
- **全架构与双系统自适应**：
  - **架构**：自动适配 `x86_64 (amd64)` 与 `aarch64 (arm64)`。
  - **发行版**：无缝支持 **Debian / Ubuntu**（Systemd）以及 **Alpine Linux**（OpenRC，已自动补齐 musl / glibc 动态运行库）。
- **开箱即用双格式输出**：部署完成直接打印标准节点分享链接（`vless://`、带跳跃端口的 `hysteria2://`、`anytls://`）与适配 **OpenClash / Clash Meta (Mihomo)** 的 YAML 配置块。
- **终端交互防跳过**：交互层显式绑定控制终端（`/dev/tty`），彻底杜绝通过管道执行时跳过输入的问题。

---

## 协议与默认配置

| 协议 | 传输层 | 默认端口 | 伪装 / SNI | 认证凭据 |
| :--- | :--- | :--- | :--- | :--- |
| **VLESS-Reality** | TCP (xtls-rprx-vision) | `443` | 自动匹配地区（如 `www.apple.com`） | UUID + Reality Keypair |
| **Hysteria 2** | UDP (QUIC) | `8443` (跳跃: `20000-50000`) | 自动匹配地区（如 `apple.com`） | 随机密码 + 自签证书 + SHA256 Pin |
| **AnyTLS** | TCP (TLS-in-TLS) | `2096` | 自动匹配地区（如 `apple.com`） | 随机密码 + 自签证书 |

> **提示**：端口与伪装域名均可自定义输入；若同时启用 Reality 与 AnyTLS 且端口冲突，脚本会自动将 AnyTLS 端口顺延至下一可用端口。

---

## 一键安装与管理命令

以 `root` 用户登录 VPS 终端后，选择以下任一方式执行：

### 1. 极简短链（推荐，字符最少）

```bash
curl -sL is.gd/nOXoWk | bash
```

或使用进程替换执行：

```bash
bash <(curl -sL is.gd/nOXoWk)
```

---

### 2. GitHub 官方源完整命令

**进程替换方式（推荐）：**
```bash
bash <(curl -fsSL [https://raw.githubusercontent.com/reman-l/vps-scripts/main/sb.sh](https://raw.githubusercontent.com/reman-l/vps-scripts/main/sb.sh))
```

**传统管道方式：**
```bash
curl -fsSL [https://raw.githubusercontent.com/reman-l/vps-scripts/main/sb.sh](https://raw.githubusercontent.com/reman-l/vps-scripts/main/sb.sh) | bash
```

> **CDN 缓存刷新提示**：若刚刚在 GitHub 修改了脚本内容，可以在 URL 末尾增加版本参数强制拉取最新代码：
> ```bash
> bash <(curl -fsSL [https://raw.githubusercontent.com/reman-l/vps-scripts/main/sb.sh?v=$RANDOM](https://raw.githubusercontent.com/reman-l/vps-scripts/main/sb.sh?v=$RANDOM))
> ```

---

### 3. 持久化为本地命令（可选）

将脚本下载至系统路径，后续即可直接通过 `sb` 命令快速配置或卸载：

```bash
curl -fsSL [https://raw.githubusercontent.com/reman-l/vps-scripts/main/sb.sh](https://raw.githubusercontent.com/reman-l/vps-scripts/main/sb.sh) -o /usr/local/bin/sb && chmod +x /usr/local/bin/sb
```

*下次使用直接在终端输入：*
```bash
sb
```

---

## 一键彻底卸载清理

如果不再需要该服务，可通过以下两种方式彻底清除：

### 方式 A：脚本交互菜单卸载
运行脚本（`curl -sL is.gd/nOXoWk | bash` 或 `sb`），在模式选择菜单中输入 **`0`** 并回车即可。

### 方式 B：终端单行强制清除命令
无需进入脚本，直接在终端执行以下整行命令即可完成深度清理：
```bash
/etc/sing-box/firewall.sh stop 2>/dev/null || true; ipset destroy china_ip 2>/dev/null || true; systemctl stop sing-box 2>/dev/null || rc-service sing-box stop 2>/dev/null || true; systemctl disable sing-box 2>/dev/null || rc-update del sing-box default 2>/dev/null || true; rm -f /etc/systemd/system/sing-box.service /etc/init.d/sing-box /usr/local/bin/sing-box /usr/local/bin/sb; rm -rf /etc/sing-box /var/log/sing-box /run/sing-box.pid; systemctl daemon-reload 2>/dev/null || true; echo "卸载完成！所有服务、配置及规则已彻底清理。"
```

---

## 防护功能使用场景建议

- **出站防溯源设置（强烈建议保持开启）**：
  - **建议选择**：`Y`（默认）。
  - **场景**：完全不影响访问 Google、YouTube、Twitter 等境外网站。当手机或路由器误开全局模式、国内应用偷跑 HTTPDNS 或国内网站诱导探测时，VPS 会在出站处直接丢弃并拒绝建立连接，彻底杜绝境内服务器日志记录 VPS IP 并被关联溯源。
- **入站屏蔽中国大陆 IP（按需谨慎开启）**：
  - **建议选择**：通过中转机（香港、专线、Realm、CDN）连接本机器时选 `Y`；直连模式下务必选 `N`（默认）。
  - **场景**：若你直接从国内宽带直连这台 VPS，开启后你自己也会被当作嗅探探测流量丢包阻断。

---

## 常用服务管理命令

### 查看配置文件与运行状态

```bash
# 查看配置文件
cat /etc/sing-box/config.json

# 测试配置文件语法
/usr/local/bin/sing-box check -c /etc/sing-box/config.json

# 查看端口监听
ss -tulpn | grep sing-box || netstat -tulpn | grep sing-box
```

### 服务启停控制

* **Debian / Ubuntu (Systemd)**:
  ```bash
  systemctl status sing-box   # 查看状态
  systemctl restart sing-box  # 重启服务 (包含防火墙规则重置)
  systemctl stop sing-box     # 停止服务 (自动清理防火墙规则)
  journalctl -u sing-box -f   # 查看实时日志
  ```

* **Alpine Linux (OpenRC)**:
  ```bash
  rc-service sing-box status  # 查看状态
  rc-service sing-box restart # 重启服务
  rc-service sing-box stop    # 停止服务
  ```

---

## 客户端支持

- **OpenClash / Clash Verge Rev / ShellClash**（建议使用 Meta / Mihomo 内核）
- **v2rayN** (Windows)
- **Shadowrocket / 小火箭** (iOS)
- **sing-box 原生客户端** (Android / iOS / macOS / Windows)
