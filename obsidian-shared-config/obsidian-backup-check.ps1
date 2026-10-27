param(
  [int]$Keep = 30,
  [string]$SharedConfig = (Join-Path $PSScriptRoot '.obsidian')
)

$ErrorActionPreference = 'Stop'

$config = (Resolve-Path -LiteralPath $SharedConfig).Path
$backupScript = Join-Path $PSScriptRoot 'obsidian-backup.ps1'
$logRoot = Join-Path $PSScriptRoot 'backups\logs'
$logFile = Join-Path $logRoot 'obsidian-backup.log'

New-Item -ItemType Directory -Path $logRoot -Force | Out-Null

function Write-BackupLog {
  param([string]$Level, [string]$Message)

  $line = '{0} [{1}] {2}' -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $Level, $Message
  Add-Content -LiteralPath $logFile -Value $line -Encoding utf8
  Write-Host $line
}

try {
  if (-not (Test-Path -LiteralPath $config -PathType Container)) {
    throw "共享配置目录不存在：$config"
  }
  if (-not (Test-Path -LiteralPath $backupScript -PathType Leaf)) {
    throw "备份脚本不存在：$backupScript"
  }

  # JSON 坏了就当不健康：保留上一份健康归档，不把损坏的配置记成最新状态。
  $jsonFiles = Get-ChildItem -LiteralPath $config -Recurse -Force -File -Filter '*.json'
  foreach ($file in $jsonFiles) {
    try {
      $null = Get-Content -Raw -LiteralPath $file.FullName | ConvertFrom-Json
    } catch {
      throw "JSON 无效：$($file.FullName)。$($_.Exception.Message)"
    }
  }

  $communityFile = Join-Path $config 'community-plugins.json'
  if (Test-Path -LiteralPath $communityFile) {
    # 5.1 的 ConvertFrom-Json 把数组当单对象返回，先赋值再 @() 展开。
    $parsedPlugins = ConvertFrom-Json -InputObject (Get-Content -Raw -LiteralPath $communityFile)
    foreach ($pluginId in @($parsedPlugins)) {
      $manifestFile = Join-Path $config "plugins\$pluginId\manifest.json"
      if (-not (Test-Path -LiteralPath $manifestFile -PathType Leaf)) {
        throw "已启用的插件缺少 manifest：$pluginId"
      }
      $manifest = Get-Content -Raw -LiteralPath $manifestFile | ConvertFrom-Json
      if ($manifest.id -ne $pluginId) {
        throw "插件 manifest id 不一致：期望 $pluginId，实际 $($manifest.id)"
      }
    }
  }

  $appearanceFile = Join-Path $config 'appearance.json'
  if (Test-Path -LiteralPath $appearanceFile) {
    $appearance = Get-Content -Raw -LiteralPath $appearanceFile | ConvertFrom-Json
    if ($appearance.cssTheme) {
      $themeCss = Join-Path $config "themes\$($appearance.cssTheme)\theme.css"
      if (-not (Test-Path -LiteralPath $themeCss -PathType Leaf)) {
        throw "当前主题文件缺失：$($appearance.cssTheme)"
      }
    }
  }

  $backupOutput = (& $backupScript -Keep $Keep -SharedConfig $config *>&1 | Out-String).Trim()
  if ($LASTEXITCODE -and $LASTEXITCODE -ne 0) {
    throw "备份命令退出码 $LASTEXITCODE。$backupOutput"
  }
  Write-BackupLog -Level 'INFO' -Message $backupOutput
} catch {
  Write-BackupLog -Level 'ERROR' -Message $_.Exception.Message
  exit 1
}
