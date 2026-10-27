# obsidian-git-sync

一套 Obsidian 知识库的 Git 同步规则：哪些文件该进仓库、哪些永远不进，多设备之间怎么避免冲突，密钥怎么不泄露。

配套一键安装脚本，装完即可用 Obsidian Git 插件在多台电脑/手机之间同步整个 vault。

> 规则不是配置截图，是几条能说清"为什么"的约定。照着做完，两台设备同时编辑也不会把笔记搞乱。

## 这套规则解决什么

| 问题 | 规则给出的答案 |
| --- | --- |
| 插件更新导致仓库三天两头冲突 | 插件代码提交，插件运行时状态不提交 |
| 手机和电脑打开同一笔记，恢复出旧版本 | 开机自动拉取 + 冲突用 rebase 而不是 merge |
| 提交记录被自动备份刷屏 | 固定提交信息 `vault backup: <时间>`，一次备份一次提交 |
| 插件 `data.json` 里的 token 被推到公开仓库 | 明确列入忽略清单，首次提交前就生效 |
| 同步上来了别人的临时文件、缓存、备份 | 忽略清单覆盖 workspace / cache / 备份 |

## 文件同步边界

**提交**（会同步到所有设备）：

- `*.md` 笔记、`.canvas` 画板、附件
- `.obsidian/` 下的可复用配置：`app.json`、`appearance.json`、`core-plugins.json`、`community-plugins.json`、`hotkeys.json`、snippets、主题
- `.obsidian/plugins/<插件>/` 的 `main.js` / `manifest.json` / `styles.css` —— 让每台设备的插件版本一致
- `.gitignore` 自身

**不提交**（每台设备各自生成）：

| 路径 | 原因 |
| --- | --- |
| `.obsidian/workspace.json`、`workspace-mobile.json` | 窗口布局，设备间互相同步会打架，还会导致面板乱跳 |
| `.obsidian/cache/`、`.obsidian/backups/` | 可再生缓存与本地备份 |
| `.obsidian/plugins/obsidian-git/obsidian_askpass.sh` | 本机生成的凭据助手脚本 |
| `.obsidian/plugins/*/data.json`（含 token 的插件） | 插件配置里常有明文口令/token，一旦提交就是泄露 |
| `*.obsidian.backup.*/`、`备份/`、`临时/` | 本地快照与草稿 |
| `杂七杂八/`、`99_敏感内容/`、`私密/` | 敏感目录，永不入库 |
| `Thumbs.db`、`.DS_Store` | 系统垃圾文件 |

> 判断标准只有一条：**换一台设备，这个文件应该长一样吗？**
> 应该 → 提交；不应该（布局、缓存、本机密钥）→ 忽略。

## 同步行为规则

在 Obsidian Git 插件里按下表设置（安装脚本可以自动写入）：

| 设置项 | 值 | 为什么 |
| --- | --- | --- |
| 提交信息 | `vault backup: {{date}}` | 一眼看出这是自动备份，不掺在手工提交里 |
| 自动提交间隔 | `10`（分钟） | 既能兜住忘保存，又不至于把记录刷成流水账 |
| 自动推送间隔 | `0`（关闭） | 推送时机交给"关闭时/手动"，避免半天内几百次网络请求 |
| 开机自动拉取 | 开启 | 先拿到别的设备的最新改动，再开始写，绝大多数冲突就此消失 |
| 推送前先拉取 | 开启 | 同上，推之前再确认一次 |
| 同步方式 | `rebase` | 线性的历史，冲突只落在你正在改的那个文件上，不会生成 merge commit |
| 自动 stash | `enabled` | rebase 前把未提交改动收起来，拉完再放回，防止"有未提交改动不能 rebase" |
| 限制在 vault 内 | 开启 | 保证插件只碰这个 vault，不会误操作上层目录 |

## 安全规则

1. **先有 `.gitignore`，再做第一次提交。** 顺序反了，敏感内容就进了历史，删掉文件也删不掉记录。
2. 任何带 token / cookie / 密码的插件 `data.json`，一律进忽略清单。
3. 公开仓库 = 世界上所有人可读。私密笔记放独立目录并忽略，或者整个仓库设为 private。
4. 提交前扫一眼 `git status`，出现意料之外的文件就是规则漏了。

## 一键安装

**Windows**

```powershell
# 在 vault 目录下执行（先关闭 Obsidian）
.\install.ps1
```

**macOS / Linux**

```bash
# 在 vault 目录下执行（先关闭 Obsidian）
chmod +x install.sh && ./install.sh
```

**可选参数**

```powershell
.\install.ps1 -VaultPath "D:\knowledge" -Remote "https://github.com/<you>/<repo>.git" -Branch main -WithPluginConfig
```

```bash
./install.sh --vault ~/knowledge --remote https://github.com/<you>/<repo>.git --branch main --with-plugin-config
```

脚本能做的事都做了：校验 vault、写忽略清单（可重复执行，不会重复写）、初始化仓库、绑定远端、按上表写入插件配置。它不碰你的笔记，也不覆盖你已有的 `.gitignore` 规则。

## 手动安装

1. Obsidian 打开 vault → 设置 → 第三方插件 → 关闭安全模式 → 浏览 → 安装 **Git** 插件，启用。
2. 在 vault 根目录 `git init`，把上面的忽略清单存成 `.gitignore`。
3. 建一个**私有**仓库（笔记基本都有隐私），`git remote add origin <url>`。
4. 插件设置里按"同步行为规则"的表逐项设置（或把脚本里的配置块贴进 `data.json`）。
5. 点插件的提交 + 推送，完成首次同步。
6. 第二台设备：`git clone` 到本地 → Obsidian 打开该目录 → 装 Git 插件 → 之后开机自动拉取。

## 冲突了怎么办

- **打开 Obsidian 后提示有冲突**：说明两台设备都改了同一篇。插件已经把两边内容合进文件，搜 `<<<<<<<` 手工挑一边删掉。
- **常见诱因**：`workspace.json` 被提交（已由忽略清单排除）、插件自动更新在主仓库里改了 `main.js`（提交前先拉取）。
- **避免方式**：写完等 10 分钟让自动提交落地再关机；换设备前先手动点一次拉取。

## 手机端

Obsidian Git 手机版用 `isomorphic-git`，不能跑本脚本。做法：先在电脑上跑完脚本并推送，手机上 `git clone`（插件内置克隆功能）后照"同步行为规则"手动设置即可。

## 目录

```
obsidian-git-sync/
├── README.md        # 本文件：规则说明
├── install.ps1      # Windows 一键安装
└── install.sh       # macOS / Linux 一键安装
```

## License

MIT
