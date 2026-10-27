param(
  [int]$Keep = 30,
  [string]$SharedConfig = (Join-Path $PSScriptRoot '.obsidian'),
  [string]$BackupRoot = (Join-Path $PSScriptRoot 'backups\scheduled')
)

$ErrorActionPreference = 'Stop'

if ($Keep -lt 1) {
  throw 'Keep 至少为 1。'
}

$config = (Resolve-Path -LiteralPath $SharedConfig).Path
if (-not (Test-Path -LiteralPath $config -PathType Container)) {
  throw "共享配置目录不存在：$config"
}

New-Item -ItemType Directory -Path $BackupRoot -Force | Out-Null

# 按固定顺序对路径和内容一起取哈希：设置、插件、主题、workspace 的任何变化
# 都会改变指纹，而同一天内没有变化就不生成重复归档。
$fingerprintLines = Get-ChildItem -LiteralPath $config -Recurse -Force -File |
  Sort-Object FullName |
  ForEach-Object {
    $relativePath = $_.FullName.Substring($config.Length).TrimStart('\')
    $hash = (Get-FileHash -Algorithm SHA256 -LiteralPath $_.FullName).Hash
    "$relativePath|$hash"
  }
$fingerprintText = $fingerprintLines -join "`n"
$fingerprintBytes = [Text.Encoding]::UTF8.GetBytes($fingerprintText)
$sha = [Security.Cryptography.SHA256]::Create()
try {
  $fingerprint = ([BitConverter]::ToString($sha.ComputeHash($fingerprintBytes)) -replace '-', '').ToLowerInvariant()
} finally {
  $sha.Dispose()
}
$latestFingerprintFile = Join-Path $BackupRoot 'latest.sha256'

if (Test-Path -LiteralPath $latestFingerprintFile) {
  $latestFingerprint = (Get-Content -Raw -LiteralPath $latestFingerprintFile).Trim()
  if ($latestFingerprint -eq $fingerprint) {
    Write-Host "Unchanged: $config"
    return
  }
}

# 先在私有暂存目录里组装压缩包：Obsidian 正在写文件时也不会在最终路径上
# 留下一个只写了一半的归档。
$timestamp = Get-Date -Format 'yyyyMMdd-HHmmss'
$archive = Join-Path $BackupRoot ("obsidian-config-$timestamp.zip")
$staging = Join-Path $BackupRoot (".staging-$timestamp")
try {
  $stagingConfig = Join-Path $staging '.obsidian'
  New-Item -ItemType Directory -Path $staging -Force | Out-Null
  Copy-Item -LiteralPath $config -Destination $stagingConfig -Recurse -Force
  Compress-Archive -LiteralPath $stagingConfig -DestinationPath $archive -CompressionLevel Optimal

  if (-not (Test-Path -LiteralPath $archive) -or (Get-Item -LiteralPath $archive).Length -eq 0) {
    throw "归档没有正确生成：$archive"
  }
  Set-Content -LiteralPath $latestFingerprintFile -Value $fingerprint -Encoding ascii
} finally {
  if (Test-Path -LiteralPath $staging) {
    Remove-Item -LiteralPath $staging -Recurse -Force
  }
}

# 保留策略只作用于计划备份；手工恢复快照留在上一级目录，不参与清理。
Get-ChildItem -LiteralPath $BackupRoot -File -Filter 'obsidian-config-*.zip' |
  Sort-Object LastWriteTime -Descending |
  Select-Object -Skip $Keep |
  Remove-Item -Force

Write-Host "Backed up: $archive"
