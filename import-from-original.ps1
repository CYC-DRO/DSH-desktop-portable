# DeepSeek Harness portable - one-time data import from the original install
# Copies sessions/credentials/browser data from the ORIGINAL installed copy
# into this portable package's Data folder. The original side wins on
# conflicts, so run this BEFORE you start using the portable version, and
# after closing the original app (it locks some files while running).
$ErrorActionPreference = 'SilentlyContinue'
$root = Split-Path -Parent $MyInvocation.MyCommand.Path

$srcHome = Join-Path $env:USERPROFILE '.dsh'
$srcUser = Join-Path $env:APPDATA '@deepseek-ai\dsh-desktop'
$dstHome = Join-Path $root 'Data\dsh-home'
$dstUser = Join-Path $root 'Data\AppData\Roaming\@deepseek-ai\dsh-desktop'

Write-Host '从原安装版导入数据（原版内容为准，覆盖同名文件）...'
if (Test-Path $srcHome) {
  robocopy $srcHome $dstHome /E /R:1 /W:1 /NFL /NDL /NP | Out-Null
  if ($LASTEXITCODE -ge 8) { Write-Host "  [x] dsh-home 导入失败（代码 $LASTEXITCODE）" -ForegroundColor Red }
  else { Write-Host '  [ok] dsh-home（登录凭据/会话/配置）' -ForegroundColor Green }
} else {
  Write-Host '  -  未找到原版 dsh-home（可能从未安装过原版），跳过'
}
if (Test-Path $srcUser) {
  robocopy $srcUser $dstUser /E /XD Cache 'Code Cache' GPUCache DawnGraphiteCache DawnWebGPUCache 'Shared Dictionary' /R:1 /W:1 /NFL /NDL /NP | Out-Null
  if ($LASTEXITCODE -ge 8) { Write-Host "  [!] 浏览器数据部分文件被占用（原版正在运行？）。关闭原版后重新运行本脚本即可补齐。" -ForegroundColor Yellow }
  else { Write-Host '  [ok] 浏览器数据（Cookies/本地存储等）' -ForegroundColor Green }
} else {
  Write-Host '  -  未找到原版浏览器数据，跳过'
}
Write-Host '导入结束。'
exit 0
