# VPS 脚本使用说明

## WARP 本地代理

`warp-proxy.sh` 使用 Cloudflare 官方 APT 源，按系统代号及架构安装 APT 候选版本，并设置 `127.0.0.1:40000` TCP SOCKS5 代理。不会主动设置全局隧道，不修改或重启 V2bX，不包含任何订阅、密钥或服务器配置。

支持范围：Ubuntu 20.04 / 22.04 / 24.04 / 26.04；Debian 11 / 12 / 13；amd64 / arm64；需要 root、systemd、可用网络。Ubuntu 20.04 和 Debian 11 仅有旧构建；具体包是否可用以官方源为准。依赖不满足会停止，不混用其他发行版源或强制降级。

## 运行

这是私有仓库，匿名 curl 无法下载。请登录 GitHub 下载 `warp-proxy.sh`，传到 VPS，检查内容后执行：

```bash
bash -n warp-proxy.sh
bash warp-proxy.sh --accept-tos
```

`--accept-tos` 明确表示同意 Cloudflare 的条款。脚本会安装软件、修改 APT 源和 WARP 模式，并启用服务开机自启。原有 WARP 连接可能短暂中断；建议保留 VPS 控制台访问能力。已有注册保留，不主动删除。不要在企业托管 WARP 或其他重要隧道环境直接执行。

APT 源和密钥有时间戳备份；脚本不是事务，失败不会自动撤销已安装的软件或配置。如果已有其他 Cloudflare 源导致 Signed-By 冲突，先人工核对并消除重复条目，不要混用发行版。

## 验证

```bash
warp-cli status
ss -lntp 'sport = :40000'
curl --proxy socks5h://127.0.0.1:40000 --max-time 20 https://www.cloudflare.com/cdn-cgi/trace
```

预期监听 `127.0.0.1:40000` 且 trace 显示 `warp=on`。检测结果只说明代理可用，不保证 IPv4 出口、指定地区、流媒体解锁或订阅地址可达。只有明确使用此代理的请求才走 WARP；V2bX 分流需要另行配置。

失败时查看 `journalctl -u warp-svc -n 80 --no-pager`。不要把注册信息、密钥或带 token 的订阅 URL 提交到仓库。

## 验证范围

发布前执行 Bash 语法检查；未在所有列出的发行版和架构上做真实安装测试。安装脚本依据官方文档与已有机器的 CLI 输出编写。

参考：[官方软件源](https://pkg.cloudflareclient.com/)、[Linux 使用说明](https://developers.cloudflare.com/warp-client/get-started/linux/)、[Cloudflare 条款](https://www.cloudflare.com/terms/)。
