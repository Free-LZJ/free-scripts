#requires -Version 5.1
<#
.SYNOPSIS
    Obsidian vault 的 Git 同步规则一键安装（Windows）。

.DESCRIPTION
    写入 .gitignore 忽略清单、初始化仓库、绑定远端，可选写入 Obsidian Git 插件配置。
    可重复执行：已有忽略清单只会跳过，不改动你手写的规则。

.PARAMETER VaultPath
    vault 根目录（含 .obsidian 的目录）。默认当前目录。

.PARAMETER Remote
    远端仓库地址。给了且本地没有 origin 时才添加。

.PARAMETER Branch
    分支名，默认 main。

.PARAMETER WithPluginConfig
    按推荐值写入 obsidian-git 插件的 data.json（执行前请关闭 Obsidian）。

.EXAMPLE
    .\install.ps1

.EXAMPLE
    .\install.ps1 -VaultPath "D:\knowledge" -Remote "https://github.com/me/vault.git" -WithPluginConfig
#>
[CmdletBinding()]
param(
    [string]$VaultPath = ".",
    [string]$Remote = "",
    [string]$Branch = "main",
    [switch]$WithPluginConfig
)

$ErrorActionPreference = "Stop"
$Marker = "# >>> obsidian-git-sync"

$ignoreBlock = @"
$Marker (由 install 脚本写入，可直接在下方追加自己的规则)

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
"@

function Write-NoBom {
    param([string]$Path, [string[]]$Lines)
    $enc = New-Object System.Text.UTF8Encoding($false)
    [System.IO.File]::WriteAllLines($Path, $Lines, $enc)
}

function Set-JsonProp {
    param($Object, [string]$Name, $Value)
    if ($Object.PSObject.Properties[$Name]) { $Object.$Name = $Value }
    else { $Object | Add-Member -NotePropertyName $Name -NotePropertyValue $Value }
}

# --- 1. 校验 vault ---
if (-not (Test-Path $VaultPath)) { throw "目录不存在：$VaultPath" }
$vault = (Resolve-Path $VaultPath).Path
if (-not (Test-Path (Join-Path $vault ".obsidian"))) {
    throw "这不是 Obsidian vault（找不到 .obsidian 目录）：$vault"
}
Write-Host "[1/4] vault 校验通过：$vault" -ForegroundColor Green

# --- 2. 写忽略清单（幂等） ---
$gitignore = Join-Path $vault ".gitignore"
$lines = @()
if (Test-Path $gitignore) {
    $lines = @([System.IO.File]::ReadAllLines($gitignore))
}

if ($lines | Where-Object { $_ -like "*$Marker*" }) {
    Write-Host "[2/4] 忽略清单已存在，跳过（如需重置请先删掉带 obsidian-git-sync 标记的段落）" -ForegroundColor Yellow
}
else {
    $merged = @($lines) + @($ignoreBlock -split "`r?`n")
    Write-NoBom -Path $gitignore -Lines $merged
    Write-Host "[2/4] 已写入忽略清单：$gitignore" -ForegroundColor Green
}

# --- 3. 初始化仓库 / 绑定远端 ---
if (-not (Test-Path (Join-Path $vault ".git"))) {
    git -C $vault init -q
    git -C $vault symbolic-ref HEAD "refs/heads/$Branch"
    Write-Host "[3/4] 已初始化仓库，分支 $Branch" -ForegroundColor Green
}
else {
    Write-Host "[3/4] 已是 Git 仓库，跳过初始化" -ForegroundColor Yellow
}

$remotes = @(git -C $vault remote 2>$null)
if ($Remote) {
    if ($remotes -contains "origin") {
        Write-Host "      origin 已存在（$((git -C $vault remote get-url origin))），未覆盖" -ForegroundColor Yellow
    }
    else {
        git -C $vault remote add origin $Remote
        Write-Host "      已绑定 origin -> $Remote" -ForegroundColor Green
    }
}
elseif (-not ($remotes -contains "origin")) {
    Write-Host "      还没配远端。建好仓库后执行：git -C `"$vault`" remote add origin <url>" -ForegroundColor Yellow
}

# --- 4. 插件配置（可选） ---
if ($WithPluginConfig) {
    $pluginDir = Join-Path $vault ".obsidian/plugins/obsidian-git"
    if (-not (Test-Path $pluginDir)) {
        Write-Host "[4/4] 未检测到 obsidian-git 插件，跳过配置写入" -ForegroundColor Yellow
        Write-Host "      先在 Obsidian 里安装并启用 Git 插件，再重跑本脚本加 -WithPluginConfig" -ForegroundColor Yellow
    }
    else {
        $dataFile = Join-Path $pluginDir "data.json"
        $cfg = $null
        if (Test-Path $dataFile) {
            Copy-Item $dataFile "$dataFile.bak" -Force
            try { $cfg = Get-Content $dataFile -Raw -Encoding UTF8 | ConvertFrom-Json } catch { $cfg = $null }
        }
        if (-not $cfg) { $cfg = New-Object PSObject }

        $recommended = [ordered]@{
            commitMessage      = "vault backup: {{date}}"
            autoCommitMessage  = "vault backup: {{date}}"
            autoSaveInterval   = 10
            autoPushInterval   = 0
            autoPullOnBoot     = $true
            pullBeforePush     = $true
            syncMethod         = "rebase"
            rebaseAutoStash    = "enabled"
            limitToVault       = $true
            disablePush        = $false
        }
        foreach ($k in $recommended.Keys) { Set-JsonProp -Object $cfg -Name $k -Value $recommended[$k] }

        $json = $cfg | ConvertTo-Json -Depth 20
        Write-NoBom -Path $dataFile -Lines ($json -split "`r?`n")
        Write-Host "[4/4] 已按推荐值写入插件配置（原文件备份为 data.json.bak）" -ForegroundColor Green
        Write-Host "      重启 Obsidian 后生效" -ForegroundColor Yellow
    }
}
else {
    Write-Host "[4/4] 跳过插件配置（需要时加 -WithPluginConfig，先关闭 Obsidian）" -ForegroundColor Yellow
}

Write-Host ""
Write-Host "下一步：" -ForegroundColor Cyan
Write-Host "  1. Obsidian 安装并启用 Git 插件"
Write-Host "  2. 插件面板点「Commit-and-sync」，完成首次推送"
Write-Host "  3. 第二台设备：git clone 后用 Obsidian 打开该目录，同样装 Git 插件"
Write-Host ""
Write-Host "规则细节见 README.md" -ForegroundColor Cyan
