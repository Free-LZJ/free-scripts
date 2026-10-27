#Requires -Version 5.1
<#
.SYNOPSIS
    多 vault 共享一份 Obsidian 配置：一键安装。

.DESCRIPTION
    把一个共享配置目录变成「所有 vault 共用的一套 .obsidian」：
      1. 准备共享配置目录
      2. 安装 knowledge-git-loader（让 Git 插件只在指定 vault 里加载）
      3. 配置白名单与启用列表
      4. 可选：把指定 vault 接入共享配置、注册每日备份任务

    可重复执行，已有配置会被备份后再改，不会覆盖你的插件设置。

.PARAMETER SharedConfig
    共享配置目录（.obsidian 的路径）。默认是本脚本所在目录下的 .obsidian。

.PARAMETER Vault
    可选：顺手把这个 vault 接入共享配置。

.PARAMETER GitVaults
    可选：允许加载 obsidian-git 的 vault 列表。不传则不修改现有白名单。

.PARAMETER RegisterTask
    注册每天 03:00 的健康检查 + 备份计划任务。

.PARAMETER TaskName
    计划任务名，默认 "Obsidian Shared Config Backup"。

.EXAMPLE
    .\install.ps1

.EXAMPLE
    .\install.ps1 -Vault "D:\notes" -GitVaults "D:\notes" -RegisterTask

.EXAMPLE
    # 脚本随处放，共享配置单独放一个目录
    .\install.ps1 -SharedConfig "E:\Obsidian-Config\.obsidian"
#>
param(
  [string]$SharedConfig = (Join-Path $PSScriptRoot '.obsidian'),
  [string]$Vault = '',
  [string[]]$GitVaults = @(),
  [switch]$RegisterTask,
  [string]$TaskName = 'Obsidian Shared Config Backup'
)

$ErrorActionPreference = 'Stop'

function Write-Section([string]$Text) {
  Write-Host ''
  Write-Host "== $Text" -ForegroundColor Cyan
}

function Backup-ThenWrite([string]$Path, [string]$Content) {
  if (Test-Path -LiteralPath $Path) {
    Copy-Item -LiteralPath $Path -Destination "$Path.bak" -Force
  }
  # 必须无 BOM：Obsidian 用 JSON.parse 读这些文件，BOM 会让它解析失败。
  # Windows PowerShell 5.1 的 -Encoding utf8 会写 BOM，所以走 .NET 写。
  $enc = New-Object System.Text.UTF8Encoding($false)
  [System.IO.File]::WriteAllText($Path, $Content, $enc)
}

# --- 0. 环境检查 ---
Write-Section '环境检查'
if ($PSVersionTable.PSVersion.Major -lt 7) {
  Write-Host '提示：PowerShell 7+ 体验更好（本脚本也兼容 5.1）。' -ForegroundColor Yellow
}
$initScript = Join-Path $PSScriptRoot 'obsidian-init.ps1'
$pluginSource = Join-Path $PSScriptRoot 'knowledge-git-loader'
if (-not (Test-Path -LiteralPath $initScript -PathType Leaf)) {
  throw "缺少 obsidian-init.ps1，请把整个目录一起拷贝：$PSScriptRoot"
}
if (-not (Test-Path -LiteralPath (Join-Path $pluginSource 'main.js') -PathType Leaf)) {
  throw "缺少围栏插件源码：$pluginSource\main.js"
}
Write-Host "脚本目录：$PSScriptRoot"

# --- 1. 共享配置目录 ---
Write-Section '共享配置目录'
if (-not (Test-Path -LiteralPath $SharedConfig -PathType Container)) {
  New-Item -ItemType Directory -Path $SharedConfig -Force | Out-Null
  Write-Host "已创建：$SharedConfig"
  Write-Host '  该目录为空时，先让 Obsidian 打开任意一个已接入的 vault 生成默认配置，再回来配白名单。' -ForegroundColor Yellow
}
$SharedConfig = (Resolve-Path -LiteralPath $SharedConfig).Path
Write-Host "使用：$SharedConfig"

# --- 2. 围栏插件 ---
Write-Section '安装 knowledge-git-loader'
$pluginTarget = Join-Path $SharedConfig 'plugins\knowledge-git-loader'
New-Item -ItemType Directory -Path $pluginTarget -Force | Out-Null
foreach ($file in @('main.js', 'manifest.json')) {
  Copy-Item -LiteralPath (Join-Path $pluginSource $file) -Destination (Join-Path $pluginTarget $file) -Force
}
Write-Host "已安装：$pluginTarget"

# --- 3. 白名单 ---
if ($GitVaults.Count -gt 0) {
  Write-Section '配置 Git 白名单'
  $resolved = @()
  foreach ($item in $GitVaults) {
    if (Test-Path -LiteralPath $item -PathType Container) {
      $resolved += (Resolve-Path -LiteralPath $item).Path
    } else {
      Write-Host "跳过不存在的目录：$item" -ForegroundColor Yellow
    }
  }
  if ($resolved.Count -eq 0) { throw '给定的 -GitVaults 没有一个有效目录。' }

  $settingsFile = Join-Path $pluginTarget 'data.json'
  $settings = @{ vaults = $resolved }
  Backup-ThenWrite -Path $settingsFile -Content ($settings | ConvertTo-Json -Depth 5)
  Write-Host ("白名单写入了 {0} 个 vault：" -f $resolved.Count)
  $resolved | ForEach-Object { Write-Host "  $_" }
}
else {
  Write-Host '未传 -GitVaults，保留现有白名单（没配过则所有 vault 都不加载 Git）。' -ForegroundColor Yellow
}

# --- 4. 全局启用列表 ---
Write-Section '调整 community-plugins.json'
$communityFile = Join-Path $SharedConfig 'community-plugins.json'
$enabled = @()
if (Test-Path -LiteralPath $communityFile) {
  # 分两步赋值：Windows PowerShell 5.1 的 ConvertFrom-Json 把 JSON 数组当成
  # 单个对象返回，写成 @(Get-Content | ConvertFrom-Json) 会包成嵌套数组。
  $parsed = ConvertFrom-Json -InputObject (Get-Content -Raw -LiteralPath $communityFile)
  $enabled = @($parsed)
} else {
  Write-Host '该目录还没有 community-plugins.json（Obsidian 尚未初始化过配置）。' -ForegroundColor Yellow
}

$changed = $false
if ($enabled -contains 'obsidian-git') {
  $enabled = @($enabled | Where-Object { $_ -ne 'obsidian-git' })
  $changed = $true
  Write-Host '移除了 obsidian-git（它必须由围栏插件按 vault 加载）'
}
if ($enabled -notcontains 'knowledge-git-loader') {
  $enabled += 'knowledge-git-loader'
  $changed = $true
  Write-Host '启用了 knowledge-git-loader'
}

if ($changed) {
  # -InputObject 才保得住数组结构；走管道时 5.1 会把单元素数组写成裸字符串。
  Backup-ThenWrite -Path $communityFile -Content (ConvertTo-Json -InputObject @($enabled))
  Write-Host '已更新启用列表（原文件备份为 .bak）'
} else {
  Write-Host '启用列表已经是正确状态，无需改动'
}

# --- 5. 接入 vault ---
if ($Vault) {
  Write-Section '接入 vault'
  & $initScript -VaultPath $Vault -SharedConfig $SharedConfig
} else {
  Write-Host ''
  Write-Host '跳过 vault 接入（需要时加 -Vault <目录>，或直接跑 obsidian-init.ps1）。' -ForegroundColor Yellow
}

# --- 6. 计划任务 ---
if ($RegisterTask) {
  Write-Section '注册计划任务'
  $checkScript = Join-Path $PSScriptRoot 'obsidian-backup-check.ps1'
  $shell = (Get-Command pwsh -ErrorAction SilentlyContinue)
  $exe = if ($shell) { $shell.Source } else { Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe' }
  try {
    $action = New-ScheduledTaskAction -Execute $exe `
      -Argument "-NoProfile -ExecutionPolicy Bypass -File `"$checkScript`" -SharedConfig `"$SharedConfig`""
    $trigger = New-ScheduledTaskTrigger -Daily -At '03:00'
    Register-ScheduledTask -TaskName $TaskName -Action $action -Trigger $trigger `
      -Description 'Obsidian 共享配置健康检查与每日备份' -Force | Out-Null
    Write-Host "已注册：$TaskName（每天 03:00）"
  } catch {
    Write-Host "注册失败：$($_.Exception.Message)" -ForegroundColor Yellow
    Write-Host "可手动执行：schtasks /Create /F /SC DAILY /ST 03:00 /TN `"$TaskName`" /TR `"`"$exe`" -NoProfile -ExecutionPolicy Bypass -File `"`"$checkScript`"`"`""
  }
}

# --- 核验 ---
Write-Section '核验'
Write-Host "共享配置：$SharedConfig"
Write-Host 'vault 联接状态：'
Write-Host '  Get-Item -Force <vault>\.obsidian | Select-Object LinkType, Target'
Write-Host '围栏插件自检：'
Write-Host "  node `"$PSScriptRoot\knowledge-git-loader.test.cjs`" `"$pluginSource`" `"$SharedConfig`""
Write-Host ''
Write-Host '完成。重新打开 Obsidian 生效。' -ForegroundColor Green
