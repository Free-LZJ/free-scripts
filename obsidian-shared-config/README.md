# obsidian-shared-config

让**多个 Obsidian vault 共用同一份 `.obsidian` 配置**：插件、主题、快捷键、编辑器设置只维护一套，改一次全部生效。

顺带解决共享配置带来的两个副作用：Git 插件只能在你指定的仓库里跑，配置每天自动备份。

## 为什么需要

多 vault 的人迟早会遇到这些问题：

| 做法 | 问题 |
| --- | --- |
| 每个 vault 各存一份 `.obsidian` | 装个插件要装 N 次；快捷键改了三个仓库两个没改 |
| 复制粘贴配置 | 一段时间后完全不知道哪份是最新的 |
| 把配置提交进每个 Git 仓库 | 配置冲突混进笔记提交历史，冲突解决起来极其恶心 |

这套方案用 **Windows Junction** 让每个 vault 的 `.obsidian` 指向同一个目录：对 Obsidian 来说它就是普通配置目录，对文件系统来说是同一份文件。

```
vault A/.obsidian  ──┐
vault B/.obsidian  ──┼──>  E:\Obsidian-Config\.obsidian
vault C/.obsidian  ──┘
```

## 三个组成部分

### 1. Junction 联接

每个 vault 的 `.obsidian` 不是副本，而是指向共享配置的 Junction。所以在任意 vault 里改设置，等价于改共享配置，不需要"反向同步"。

### 2. knowledge-git-loader（围栏插件）

共享配置意味着 `community-plugins.json` 也是共享的——一旦启用 `obsidian-git`，**每个** vault 都会加载它，每个 vault 都变成一个 Git 仓库。这通常不是你要的。

所以全局启用列表里放的是这个 20 行的围栏插件，它读自己的 `data.json`：

```json
{ "vaults": ["D:\\notes", "D:\\work-notes"] }
```

只在白名单里的 vault 加载 `obsidian-git`，其余 vault 保持干净：

```js
// main.js 核心逻辑
const settings = (await this.loadData()) || {};
const vaults = Array.isArray(settings.vaults) ? settings.vaults : [];
this.allowed = vaults.some(item =>
  typeof item === "string" && path.resolve(item).toLowerCase() === current);
if (!this.allowed) return;                       // 不在白名单：什么都不做
await this.app.plugins.enablePlugin("obsidian-git");
```

白名单支持多个仓库，路径忽略大小写和尾部斜杠。没有 `data.json` 时谁都不加载——默认安全。

### 3. 指纹备份

`obsidian-backup.ps1` 对配置目录里所有文件算 SHA256 指纹，**内容没变就不生成归档**，所以定时任务不会堆出一堆一模一样的 zip。默认保留最近 30 份。

`obsidian-backup-check.ps1` 在备份前先体检：JSON 是否有效、启用的插件有没有 manifest 且 id 对得上、主题文件是否存在。坏了就只记日志不备份，上一份健康归档保持原样。

## 一键安装

**场景 A：从零开始（脚本和配置放同一目录）**

```powershell
git clone https://github.com/Free-LZJ/free-scripts.git
cd free-scripts\obsidian-shared-config
.\install.ps1 -Vault "D:\my-notes" -GitVaults "D:\my-notes" -RegisterTask
```

**场景 B：已有配置目录，只是想要脚本**

```powershell
.\install.ps1 -SharedConfig "E:\Obsidian-Config\.obsidian" -GitVaults "D:\notes"
```

安装脚本做的四件事：

1. 创建/校验共享配置目录
2. 安装围栏插件到 `.obsidian/plugins/knowledge-git-loader/`
3. 把 `obsidian-git` 从全局启用列表移除，加入 `knowledge-git-loader`（原文件备份 `.bak`）
4. 可选：接入指定 vault、注册每天 03:00 的备份任务

重复执行是安全的：配置只在需要时改，改之前都备份。

## 日常操作

```powershell
# 把新 vault 接入共享配置（先关掉那个 vault 的 Obsidian 窗口）
.\obsidian-init.ps1 "D:\project\new-vault"

# 或者用简写（PATH 里有脚本目录时）
obsidian-init D:\project\new-vault

# 核验联接
Get-Item -Force D:\project\new-vault\.obsidian | Select-Object LinkType, Target
# LinkType : Junction
# Target   : E:\Obsidian-Config\.obsidian

# 手动备份（内容没变会输出 Unchanged）
.\obsidian-backup.ps1

# 体检 + 备份（计划任务跑的就是这个）
.\obsidian-backup-check.ps1

# 围栏逻辑自检
node .\knowledge-git-loader.test.cjs .\knowledge-git-loader "E:\Obsidian-Config\.obsidian"
```

`obsidian-init` 的行为：

| 情况 | 动作 |
| --- | --- |
| 已正确联接 | 输出 `Already linked`，不做任何修改 |
| 存在独立 `.obsidian` | **删除它**，换成 Junction（想保留先自己拷走） |
| 没有 `.obsidian` | 直接创建 Junction |

> 接入前请关闭对应 vault 的 Obsidian，否则正在写的配置会被删除动作打断。

## 参数

**install.ps1**

| 参数 | 默认 | 说明 |
| --- | --- | --- |
| `-SharedConfig` | `.\\.obsidian` | 共享配置目录路径 |
| `-Vault` | 空 | 顺手接入这个 vault |
| `-GitVaults` | 空 | Git 白名单，多个用逗号分隔；不传则不改动 |
| `-RegisterTask` | 关 | 注册每日备份任务 |
| `-TaskName` | `Obsidian Shared Config Backup` | 任务名，已存在同名任务时传这个覆盖 |

**obsidian-init.ps1**

| 参数 | 默认 | 说明 |
| --- | --- | --- |
| `-VaultPath` | 当前目录 | 要接入的 vault |
| `-SharedConfig` | `.\\.obsidian` | 共享配置目录 |
| `-Quiet` | 关 | 只在出错时输出 |

**obsidian-backup.ps1**

| 参数 | 默认 | 说明 |
| --- | --- | --- |
| `-Keep` | `30` | 保留最近几份归档 |
| `-SharedConfig` | `.\\.obsidian` | 共享配置目录 |
| `-BackupRoot` | `.\\backups\\scheduled` | 归档存放位置 |

## 恢复

```powershell
# 1. 先停掉 Obsidian（所有 vault）
# 2. 备份当前状态，再把归档解压回去
Expand-Archive .\backups\scheduled\obsidian-config-20260101-030000.zip -DestinationPath E:\Obsidian-Config\restore-staging
# 3. 用解压出来的 .obsidian 覆盖共享配置，然后重新打开 Obsidian
```

因为所有 vault 共用这一份，恢复一次就等于全部恢复。

## 平台说明

Junction 是 Windows 的能力，所以接入脚本限定 Windows。macOS / Linux 用符号链接等价实现：

```bash
ln -s /path/to/shared/.obsidian /path/to/vault/.obsidian
```

备份脚本（`obsidian-backup*.ps1`）是纯 PowerShell，装了 pwsh 的 macOS/Linux 同样能跑。

## 目录结构

```
obsidian-shared-config/
├── install.ps1                  # 一键安装
├── obsidian-init.ps1            # 把 vault 接入共享配置
├── obsidian-init.cmd            # 命令行入口（obsidian-init）
├── obsidian-backup.ps1          # 指纹备份
├── obsidian-backup-check.ps1    # 体检 + 备份（计划任务用）
├── knowledge-git-loader/        # 围栏插件源码
│   ├── main.js
│   └── manifest.json
├── knowledge-git-loader.test.cjs # 围栏逻辑自检（9 项）
└── .gitignore                   # 排除 .obsidian/ 与 backups/，避免把配置和归档提交上去
```

共享配置目录的形态（由 Obsidian 自己维护）：

```
<共享配置目录>/
├── app.json / appearance.json / community-plugins.json / ...
├── plugins/
│   └── knowledge-git-loader/
│       ├── main.js
│       ├── manifest.json
│       └── data.json          ← 白名单，就是在这里配
└── themes/
```

## 排错

| 现象 | 原因与处理 |
| --- | --- |
| 新 vault 打开后插件全没了 | `.obsidian` 没联接上，`Get-Item -Force` 看 LinkType 是不是 Junction |
| 每个 vault 都弹 Git 面板 | `community-plugins.json` 里被手动加回了 `obsidian-git`，重跑 `install.ps1` |
| 所有 vault 都没有 Git | 检查白名单 `data.json` 里是不是当前 vault 的绝对路径 |
| 改配置只影响了一个 vault | 说明那个 vault 还是独立配置，`obsidian-init` 接一下 |
| 备份总是 `Unchanged` | 配置没变，正常。要强制归档就删掉 `backups\scheduled\latest.sha256` |

## License

MIT
