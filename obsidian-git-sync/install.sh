#!/usr/bin/env bash
# obsidian-git-sync 一键安装（macOS / Linux）
# 用法: ./install.sh [--vault PATH] [--remote URL] [--branch main] [--with-plugin-config]
set -euo pipefail

VAULT="."
REMOTE=""
BRANCH="main"
WITH_PLUGIN=0
MARKER="# >>> obsidian-git-sync"

while [ $# -gt 0 ]; do
  case "$1" in
    --vault) VAULT="$2"; shift 2 ;;
    --remote) REMOTE="$2"; shift 2 ;;
    --branch) BRANCH="$2"; shift 2 ;;
    --with-plugin-config) WITH_PLUGIN=1; shift ;;
    -h|--help) sed -n '2,3p' "$0"; exit 0 ;;
    *) echo "未知参数: $1" >&2; exit 2 ;;
  esac
done

[ -d "$VAULT" ] || { echo "目录不存在: $VAULT" >&2; exit 1; }
VAULT="$(cd "$VAULT" && pwd)"
[ -d "$VAULT/.obsidian" ] || { echo "这不是 Obsidian vault（找不到 .obsidian 目录）: $VAULT" >&2; exit 1; }
echo "[1/4] vault 校验通过: $VAULT"

# --- 2. 忽略清单（幂等） ---
GITIGNORE="$VAULT/.gitignore"
if [ -f "$GITIGNORE" ] && grep -qF "$MARKER" "$GITIGNORE"; then
  echo "[2/4] 忽略清单已存在，跳过"
else
  # 文件末尾没有换行时先补一个，避免新规则粘连到上一行
  [ -s "$GITIGNORE" ] && echo >> "$GITIGNORE"
  cat >> "$GITIGNORE" <<EOF
$MARKER (由 install 脚本写入，可直接在下方追加自己的规则)

# --- Obsidian 运行时状态：每台设备各自生成，同步会打架 ---
.obsidian/workspace.json
.obsidian/workspace-mobile.json
.obsidian/cache/
.obsidian/backups/
.obsidian/plugins/obsidian-git/obsidian_askpass.sh

# --- 可能含 token / 密码的插件配置 ---
.obsidian/plugins/github-publish/data.json

# --- 本地备份与草稿 ---
*.obsidian.backup.*/
备份/
临时/

# --- 敏感目录（按需改名增删）---
杂七杂八/
99_敏感内容/
私密/

# --- 系统垃圾文件 ---
Thumbs.db
desktop.ini
.DS_Store
# <<< obsidian-git-sync
EOF
  echo "[2/4] 已写入忽略清单: $GITIGNORE"
fi

# --- 3. 仓库初始化 / 远端 ---
if [ ! -d "$VAULT/.git" ]; then
  git -C "$VAULT" init -q
  git -C "$VAULT" symbolic-ref HEAD "refs/heads/$BRANCH"
  echo "[3/4] 已初始化仓库，分支 $BRANCH"
else
  echo "[3/4] 已是 Git 仓库，跳过初始化"
fi

if [ -n "$REMOTE" ]; then
  if git -C "$VAULT" remote | grep -qx origin; then
    echo "      origin 已存在（$(git -C "$VAULT" remote get-url origin)），未覆盖"
  else
    git -C "$VAULT" remote add origin "$REMOTE"
    echo "      已绑定 origin -> $REMOTE"
  fi
elif ! git -C "$VAULT" remote | grep -qx origin; then
  echo "      还没配远端。建好仓库后执行: git -C \"$VAULT\" remote add origin <url>"
fi

# --- 4. 插件配置（可选） ---
PLUGIN_DIR="$VAULT/.obsidian/plugins/obsidian-git"
if [ "$WITH_PLUGIN" -eq 1 ]; then
  if [ ! -d "$PLUGIN_DIR" ]; then
    echo "[4/4] 未检测到 obsidian-git 插件，跳过配置写入"
    echo "      先在 Obsidian 里安装并启用 Git 插件，再重跑 --with-plugin-config"
  elif ! command -v python3 >/dev/null 2>&1; then
    echo "[4/4] 需要 python3 来合并 JSON，当前环境没有。请按 README 手动设置插件项"
  else
    python3 - "$PLUGIN_DIR" <<'PY'
import json, os, shutil, sys

plugin_dir = sys.argv[1]
path = os.path.join(plugin_dir, "data.json")
recommended = {
    "commitMessage": "vault backup: {{date}}",
    "autoCommitMessage": "vault backup: {{date}}",
    "autoSaveInterval": 10,
    "autoPushInterval": 0,
    "autoPullOnBoot": True,
    "pullBeforePush": True,
    "syncMethod": "rebase",
    "rebaseAutoStash": "enabled",
    "limitToVault": True,
    "disablePush": False,
}

cfg = {}
if os.path.exists(path):
    try:
        with open(path, encoding="utf-8") as f:
            cfg = json.load(f)
    except Exception:
        cfg = {}
    shutil.copy2(path, path + ".bak")

cfg.update(recommended)
with open(path, "w", encoding="utf-8") as f:
    json.dump(cfg, f, ensure_ascii=False, indent=2)
PY
    echo "[4/4] 已按推荐值写入插件配置（原文件备份为 data.json.bak）"
    echo "      重启 Obsidian 后生效"
  fi
else
  echo "[4/4] 跳过插件配置（需要时加 --with-plugin-config，先关闭 Obsidian）"
fi

echo ""
echo "下一步："
echo "  1. Obsidian 安装并启用 Git 插件"
echo "  2. 插件面板点「Commit-and-sync」，完成首次推送"
echo "  3. 第二台设备：git clone 后用 Obsidian 打开该目录，同样装 Git 插件"
echo ""
echo "规则细节见 README.md"
