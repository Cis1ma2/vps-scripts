#!/usr/bin/env bash
# Configure official Cloudflare WARP as a local TCP proxy, not full-tunnel mode.
set -Eeuo pipefail
export LC_ALL=C
export DEBIAN_FRONTEND=noninteractive
trap 'echo "失败：请检查上面的错误。脚本不会自动回滚或切换全局 WARP。" >&2' ERR
die() { echo "错误：$*" >&2; exit 1; }

# Explicit consent is required even in unattended installations.
[ "${1:-}" = "--accept-tos" ] || die "阅读 Cloudflare 使用条款后，使用 bash warp-proxy.sh --accept-tos 执行"
[ "$(id -u)" -eq 0 ] || die "请以 root 执行"
[ -r /etc/os-release ] || die "无法识别系统"
. /etc/os-release
case "${ID}:${VERSION_ID}" in
  ubuntu:20.04) suite=focal ;;
  ubuntu:22.04) suite=jammy ;;
  ubuntu:24.04) suite=noble ;;
  ubuntu:26.04) suite=resolute ;;
  debian:11) suite=bullseye ;;
  debian:12) suite=bookworm ;;
  debian:13) suite=trixie ;;
  *) die "仅适配 Ubuntu 20.04/22.04/24.04/26.04 和 Debian 11/12/13" ;;
esac
command -v apt-get >/dev/null || die "需要 APT"
[ -d /run/systemd/system ] || die "需要运行中的 systemd"
arch="$(dpkg --print-architecture)"
case "$arch" in amd64|arm64) ;; *) die "不支持架构：$arch" ;; esac
printf '系统：%s\n软件源：%s\n架构：%s\n' "$PRETTY_NAME" "$suite" "$arch"
if [ "$suite" = focal ] || [ "$suite" = bullseye ]; then
  echo "提示：该发行版仅保留旧构建，不代表仍获官方完整支持。"
fi

echo '[1/6] 安装基础工具'
apt-get update
apt-get install -y --no-install-recommends ca-certificates curl gnupg iproute2
listeners="$(ss -H -lntp 'sport = :40000')"
if [ -n "$listeners" ]; then
  if printf '%s\n' "$listeners" | grep -v '"warp-svc"' | grep -q .; then
    die "40000 端口被其他进程占用"
  fi
fi

echo '[2/6] 配置官方软件源'
key_path=/usr/share/keyrings/cloudflare-warp-archive-keyring.gpg
repo_path=/etc/apt/sources.list.d/cloudflare-client.list
stamp="$(date +%Y%m%d-%H%M%S)"
[ ! -f "$key_path" ] || cp -a "$key_path" "${key_path}.bak.${stamp}"
[ ! -f "$repo_path" ] || cp -a "$repo_path" "${repo_path}.bak.${stamp}"
install -d -m 0755 /usr/share/keyrings
curl -fsSL --retry 3 --connect-timeout 10 --max-time 60 \
  https://pkg.cloudflareclient.com/pubkey.gpg |
  gpg --batch --yes --dearmor --output "$key_path"
chmod 0644 "$key_path"
printf 'deb [arch=%s signed-by=%s] https://pkg.cloudflareclient.com/ %s main\n' \
  "$arch" "$key_path" "$suite" > "$repo_path"
apt-get update

echo '[3/6] 检查并安装候选版本'
apt-cache policy cloudflare-warp
candidate="$(apt-cache policy cloudflare-warp | awk '/Candidate:/ {print $2; exit}')"
[ -n "$candidate" ] && [ "$candidate" != '(none)' ] || die "没有可用候选包"
echo "APT 候选版本：$candidate"
apt-get --simulate install --no-install-recommends "cloudflare-warp=$candidate"
apt-get install -y --no-install-recommends "cloudflare-warp=$candidate"
warp-cli --version

echo '[4/6] 启动服务并检查注册'
systemctl enable --now warp-svc
ready=0
for attempt in $(seq 1 15); do
  if warp-cli --accept-tos settings >/dev/null 2>&1; then ready=1; break; fi
  sleep 2
done
[ "$ready" -eq 1 ] || die "warp-svc 未就绪，请检查 journalctl -u warp-svc"
if warp-cli --accept-tos registration show >/dev/null 2>&1; then
  echo '保留已有注册。'
else
  warp-cli --accept-tos registration new
fi

echo '[5/6] 配置本地代理'
warp-cli --accept-tos mode proxy
warp-cli --accept-tos proxy port 40000
warp-cli --accept-tos connect

echo '[6/6] 验证出口'
passed=0
trace=''
for attempt in $(seq 1 6); do
  if trace="$(curl -fsS --proxy socks5h://127.0.0.1:40000 \
    --connect-timeout 5 --max-time 15 https://www.cloudflare.com/cdn-cgi/trace)"; then
    if printf '%s\n' "$trace" | grep -qx 'warp=on'; then passed=1; break; fi
  fi
  sleep 2
done
warp-cli --accept-tos status
listeners="$(ss -H -lntp 'sport = :40000')"
printf '%s\n' "$listeners"
# Fail closed if the listener is exposed beyond IPv4 loopback.
if ! printf '%s\n' "$listeners" | awk '
  NF {n++; if ($4 != "127.0.0.1:40000") bad=1}
  END {exit !(n > 0 && !bad)}'; then
  warp-cli --accept-tos disconnect || true
  die "监听地址不符合 127.0.0.1:40000 要求，已尝试断开 WARP"
fi
[ "$passed" -eq 1 ] || die "未通过出口测试；不要继续修改 V2bX"
printf '\n%s\n' "$trace"
printf '\n完成：本地 SOCKS5 127.0.0.1:40000；warp-svc 已启用开机自启。\n'
echo '未修改或重启 V2bX；不保证出口为 IPv4 或订阅服务可访问。'
