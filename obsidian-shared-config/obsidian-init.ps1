param(
  [Parameter(Position = 0)]
  [string]$VaultPath = (Get-Location).Path,

  # 共享配置目录。默认是本脚本所在目录下的 .obsidian。
  [string]$SharedConfig = (Join-Path $PSScriptRoot '.obsidian'),

  [switch]$Quiet
)

$ErrorActionPreference = 'Stop'

function Write-Step([string]$Text) {
  if (-not $Quiet) { Write-Host $Text }
}

# 只把 vault 挂到唯一的共享配置上。共享配置有自己的备份生命周期，
# 在每个 vault 旁再留一份副本会变成多个互相竞争的事实来源。
$globalConfig = (Resolve-Path -LiteralPath $SharedConfig).Path
if (-not (Test-Path -LiteralPath $globalConfig -PathType Container)) {
  throw "共享配置目录不存在：$globalConfig"
}

$vault = (Resolve-Path -LiteralPath $VaultPath).Path
$targetConfig = Join-Path $vault '.obsidian'

if (Test-Path -LiteralPath $targetConfig) {
  $item = Get-Item -LiteralPath $targetConfig -Force
  $targets = @($item.Target)
  if ($item.LinkType -in @('Junction', 'SymbolicLink') -and $targets -contains $globalConfig) {
    Write-Step "Already linked: $targetConfig -> $globalConfig"
    return
  }

  # 非共享配置在这里被有意丢弃。要保留内容请先跑 obsidian-backup.ps1，
  # 备份的是共享配置这一份，而不是每个 vault 各存一份。
  Remove-Item -LiteralPath $targetConfig -Recurse -Force
  Write-Step "Removed local config: $targetConfig"
}

# Junction 不需要管理员权限，且能被 Obsidian 正常当作普通目录读写。
cmd /c mklink /J "$targetConfig" "$globalConfig" | Write-Host
Write-Step "Linked: $targetConfig -> $globalConfig"
