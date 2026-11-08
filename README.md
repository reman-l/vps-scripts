# sing-box 多协议极简一键部署脚本

基于官方最新核心构建的轻量级代理服务一键脚本。支持 **VLESS-Reality**、**Hysteria 2** 与 **AnyTLS** 协议的任意组合部署，自动检测 CPU 架构与操作系统初始化环境，零依赖快速落地。

---

## 核心特性

- **多协议自由组合**：支持交互式自由选择单协议、双协议或三协议共存（直接回车即默认全选）。
- **全架构与系统自适应**：
  - **架构**：自动识别并适配 `x86_64 (amd64)` 与 `aarch64 (arm64)`。
  - **发行版**：无缝支持 **Debian** / **Ubuntu**（Systemd）以及 **Alpine Linux**（OpenRC，已自动补齐 musl / glibc 动态链接库兼容）。
- **零配置凭据生成**：
  - Reality：自动生成 UUID、ShortID 与 X25519 密钥对（公私钥）。
  - Hy2 / AnyTLS：自动签发 10 年有效期椭圆曲线（EC prime256v1）自签名证书，并提取 SHA-256 指纹。
- **开箱即用双格式输出**：部署完成后直接输出标准节点分享链接（`vless://`、`hysteria2://`、`anytls://`）与适配 **OpenClash / Clash Meta (Mihomo)** 的 YAML 配置块。
- **纯终端交互安全**：输入层显式绑定控制终端（`/dev/tty`），彻底解决传统 `curl | bash` 管道导致 `read` 无法输入跳过的问题。

---

## 协议与默认端口

| 协议 | 传输层 | 默认端口 | 伪装 / SNI | 认证凭据 |
| :--- | :--- | :--- | :--- | :--- |
| **VLESS-Reality** | TCP (xtls-rprx-vision) | `443` | `www.apple.com` | UUID + Reality Keypair |
| **Hysteria 2** | UDP (QUIC) | `8443` | `apple.com` | 随机密码 + 自签证书 + SHA256 Pin |
| **AnyTLS** | TCP (TLS-in-TLS) | `2096` | `apple.com` | 随机密码 + 自签证书 |

> **提示**：若同时启用 Reality 与 AnyTLS 且端口冲突，脚本会自动将 AnyTLS 端口自动顺延至下一可用端口。

---

## 一键安装命令

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

将脚本下载至系统可执行路径，后续即可直接通过 `sb` 命令快速配置：

```bash
curl -fsSL [https://raw.githubusercontent.com/reman-l/vps-scripts/main/sb.sh](https://raw.githubusercontent.com/reman-l/vps-scripts/main/sb.sh) -o /usr/local/bin/sb && chmod +x /usr/local/bin/sb
```

*下次使用仅需在终端输入：*
```bash
sb
```

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
  systemctl restart sing-box  # 重启服务
  systemctl stop sing-box     # 停止服务
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

- **OpenClash / Clash Verge Rev / ShellClash**（推荐使用 Meta / Mihomo 内核）
- **v2rayN** (Windows)
- **Shadowrocket / 小火箭** (iOS)
- **sing-box 原生客户端** (Android / iOS / macOS / Windows)
