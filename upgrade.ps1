# DeepSeek Harness portable - upgrade script
# Replaces the app files with a newer version while keeping Data\ and all
# launcher scripts untouched. The app itself is inherently portable (bootstrap
# in resources\app), so after the file swap nothing else needs re-applying.
#
# Usage:
#   upgrade.ps1                      -> download the latest nightly and install it
#   upgrade.ps1 <path-to-installer>  -> use a locally downloaded installer exe
#
# Two unpack strategies, tried in order:
#   1. 7-Zip (clean extraction, no side effects) when available.
#   2. The official NSIS installer itself, run silently into a staging
#      directory INSIDE Data\ with the same environment redirection as
#      dsh.cmd. The installer writes a few transient registry entries
#      (uninstall entry, dsh:// protocol) and a Start Menu shortcut;
#      this script deletes all of them afterwards, so nothing persists
#      outside the portable folder.
param([string]$InstallerPath, [switch]$FromApp, [switch]$NoRelaunch)
$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $MyInvocation.MyCommand.Path
$exe  = Join-Path $root 'DeepSeek Harness.exe'
$feed = 'https://download.deepseek.com/dsh-desk/feeds/win-x64/'

function Fail($msg) { Write-Host "[x] $msg" -ForegroundColor Red; exit 1 }

# 0. The app must not be running (its files are about to be replaced).
#    When triggered from inside the app (-FromApp), give it time to exit.
if ($FromApp) {
  for ($i = 0; $i -lt 90; $i++) {
    if (-not (Get-Process -Name 'DeepSeek Harness' -ErrorAction SilentlyContinue)) { break }
    Start-Sleep -Seconds 1
  }
}
if (Get-Process -Name 'DeepSeek Harness' -ErrorAction SilentlyContinue) {
  Fail 'DeepSeek Harness 仍在运行，请先退出应用（含托盘图标），再运行升级。'
}
if (-not (Test-Path $exe)) { Fail "找不到 $exe，请在便携包根目录运行本脚本。" }

$updates = Join-Path $root 'Data\updates'
New-Item -ItemType Directory -Force -Path $updates | Out-Null

# Registry/shortcut cleanup: run before (stale leftovers) and after (this run).
function Remove-InstallerSideEffects {
  $uninsKey = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Uninstall'
  Get-ChildItem $uninsKey -ErrorAction SilentlyContinue | ForEach-Object {
    $prop = Get-ItemProperty $_.PSPath -ErrorAction SilentlyContinue
    $dn = "$($prop.DisplayName)"
    $loc = "$($prop.InstallLocation)"
    if ($dn -like '*DeepSeek Harness*' -and $loc -like "$root*") {
      Remove-Item $_.PSPath -Recurse -Force -ErrorAction SilentlyContinue
      Write-Host "  已清理安装器注册表残留: $($_.PSChildName)"
    }
  }
  # Only remove the dsh:// key when it points into this package; another
  # install's registration must survive.
  $protoCmd = (Get-ItemProperty 'HKCU:\Software\Classes\dsh\shell\open\command' -ErrorAction SilentlyContinue).'(default)'
  if ("$protoCmd" -like "$root*") {
    Remove-Item 'HKCU:\Software\Classes\dsh' -Recurse -Force -ErrorAction SilentlyContinue
  }
  # The CLI-command ownership key: remove only when it points at this package.
  $cmdDir = (Get-ItemProperty 'HKCU:\Software\DeepSeekHarness\Command' -ErrorAction SilentlyContinue).Directory
  if ("$cmdDir" -like "$root*") {
    Remove-Item 'HKCU:\Software\DeepSeekHarness' -Recurse -Force -ErrorAction SilentlyContinue
  }
  $sm = Join-Path $env:APPDATA 'Microsoft\Windows\Start Menu\Programs'
  Get-ChildItem $sm -Filter '*DeepSeek*' -ErrorAction SilentlyContinue |
    Remove-Item -Force -ErrorAction SilentlyContinue
}
Write-Host '清理历史安装器残留...'
Remove-InstallerSideEffects

# 1. Obtain the new installer.
if (-not $InstallerPath) {
  Write-Host "正在获取最新版本信息: $feed"
  try {
    $latest = Invoke-WebRequest -UseBasicParsing ($feed + 'latest.yml') -TimeoutSec 30
  } catch { Fail "下载版本信息失败：$($_.Exception.Message)" }
  $file = ($latest.Content -split "`n" | Where-Object { $_ -match '^\s*path:' }) -replace '^\s*path:\s*',''
  $file = ("$file").Trim()
  if (-not $file) { Fail 'latest.yml 中没有找到 path 字段。' }
  $url = $feed + $file
  $InstallerPath = Join-Path $updates $file
  Write-Host "正在下载新版本安装包: $url"
  try {
    Invoke-WebRequest -UseBasicParsing $url -OutFile $InstallerPath -TimeoutSec 3600
  } catch { Fail "下载安装包失败：$($_.Exception.Message)" }
}
if (-not (Test-Path $InstallerPath)) { Fail "找不到安装包：$InstallerPath" }
Write-Host "使用安装包：$InstallerPath"

# Environment redirection, same as dsh.cmd: the installer and everything it
# spawns only ever sees Data\ as the user-profile location.
$env:APPDATA            = Join-Path $root 'Data\AppData\Roaming'
$env:LOCALAPPDATA       = Join-Path $root 'Data\AppData\Local'
$env:TEMP               = Join-Path $root 'Data\Temp'
$env:TMP                = Join-Path $root 'Data\Temp'
$env:HOME               = Join-Path $root 'Data\home'
$env:DSH_HOME           = Join-Path $root 'Data\dsh-home'
$env:PNPM_HOME          = Join-Path $root 'Data\pnpm'
$env:npm_config_store_dir = Join-Path $root 'Data\pnpm-store'
$env:DSH_TELEMETRY_DISABLED = '1'

$stage = Join-Path $updates ('stage-' + [guid]::NewGuid().ToString('N').Substring(0,8))
New-Item -ItemType Directory -Force -Path $stage | Out-Null

$seven = $null
foreach ($c in @('7z.exe', (Join-Path $env:ProgramFiles '7-Zip\7z.exe'),
                 (Join-Path ${env:ProgramFiles(x86)} '7-Zip\7z.exe'))) {
  $resolved = Get-Command $c -ErrorAction SilentlyContinue
  if ($resolved) { $seven = $resolved.Source; break }
}

if ($seven) {
  # ---- Strategy 1: clean 7z extraction (installer exe -> app-64.7z -> files)
  Write-Host '使用 7-Zip 解包（第一阶段）...'
  & $seven x $InstallerPath ("-o$stage") -y | Out-Null
  if ($LASTEXITCODE -ne 0) { Fail '第一阶段的 7z 解包失败。' }
  $inner = Get-ChildItem $stage -Filter '*.7z' | Select-Object -First 1
  if ($inner) {
    Write-Host '解包应用文件（第二阶段）...'
    & $seven x $inner.FullName ("-o$stage") -aoa -y | Out-Null
    if ($LASTEXITCODE -ne 0) { Fail '第二阶段的 7z 解包失败。' }
  }
} else {
  # ---- Strategy 2: let the official NSIS installer do the unpacking,
  # ---- silently, into the staging dir via /D= (raw command line, since
  # ---- NSIS requires /D= to be last and unquoted).
  Write-Host '未找到 7-Zip，改用官方安装器静默解包（目标锁定在 Data\ 内的暂存目录）...'
  # Remember any previously installed copy OUTSIDE the portable folder so we
  # can restore it if the installer insists on reusing that location.
  $uninsKey = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Uninstall'
  $prevLoc = $null
  Get-ChildItem $uninsKey -ErrorAction SilentlyContinue | ForEach-Object {
    $prop = Get-ItemProperty $_.PSPath -ErrorAction SilentlyContinue
    $loc = "$($prop.InstallLocation)".TrimEnd('\')
    if ("$($prop.DisplayName)" -like '*DeepSeek Harness*' -and $loc -and
        -not ($loc -like "$root*") -and (Test-Path (Join-Path $loc 'DeepSeek Harness.exe'))) {
      $prevLoc = $loc
    }
  }

  $psi = New-Object Diagnostics.ProcessStartInfo
  $psi.FileName = $InstallerPath
  $psi.Arguments = "/S /D=$stage"
  $psi.UseShellExecute = $false
  $pr = [Diagnostics.Process]::Start($psi)
  $pr.WaitForExit()
  if ($pr.ExitCode -ne 0) { Fail "官方安装器静默运行失败（退出码 $($pr.ExitCode)）。" }

  if (-not (Test-Path (Join-Path $stage 'DeepSeek Harness.exe'))) {
    # The installer ignored /D and reused a previous location outside the
    # package: move those files into the stage, then reinstall that copy so
    # the external install ends up exactly as it was.
    if ($prevLoc) {
      Write-Host "  安装器复用了旧位置 $prevLoc，正在把新文件迁移进便携包并恢复原安装..."
      robocopy $prevLoc $stage /E /MOVE /R:1 /W:1 /NFL /NDL /NP | Out-Null
      if ($LASTEXITCODE -ge 8) { Fail "无法从 $prevLoc 迁移文件。" }
      $psi2 = New-Object Diagnostics.ProcessStartInfo
      $psi2.FileName = $InstallerPath
      $psi2.Arguments = "/S /D=$prevLoc"
      $psi2.UseShellExecute = $false
      $pr2 = [Diagnostics.Process]::Start($psi2)
      $pr2.WaitForExit()
      if (-not (Test-Path (Join-Path $prevLoc 'DeepSeek Harness.exe'))) {
        Fail "原安装位置 $prevLoc 未能自动恢复，请手动重新运行官方安装器。"
      }
      Write-Host '  原安装已恢复。'
    } else {
      # Fresh machine: the installer used its default dir under our
      # redirected LOCALAPPDATA (inside Data\).
      $candidates = @(
        (Join-Path $env:LOCALAPPDATA 'Programs\DeepSeek Harness'),
        (Join-Path $env:LOCALAPPDATA 'Programs\dsh-desktop')
      )
      $installed = $candidates | Where-Object { Test-Path (Join-Path $_ 'DeepSeek Harness.exe') } | Select-Object -First 1
      if (-not $installed) { Fail '找不到安装器解包出来的应用目录。' }
      Write-Host "  安装器输出目录：$installed"
      Move-Item $installed $stage -Force
      # Drop empty parent dirs left behind (inside Data\, but keep things tidy).
      $prog = Split-Path -Parent $installed
      Get-ChildItem $prog -Directory -ErrorAction SilentlyContinue |
        Where-Object { -not (Get-ChildItem $_.FullName -ErrorAction SilentlyContinue) } |
        Remove-Item -Force -ErrorAction SilentlyContinue
    }
  }
}

# Remove installer-owned noise so it never lands in the portable root.
Remove-Item -Force -ErrorAction SilentlyContinue (Join-Path $stage 'app-64.7z')
Get-ChildItem $stage -Filter 'Uninstall*.exe' -ErrorAction SilentlyContinue |
  Remove-Item -Force -ErrorAction SilentlyContinue

# Merge over the portable root. Robocopy /E never deletes, so Data\,
# dsh.cmd, *.bat, *.ps1 and resources\portable\ are always preserved.
# NOTE: the merge restores the stock app.asar, wiping the portability patch -
# re-apply it right away with the bundled node (self-healing).
Write-Host '正在覆盖应用文件...'
robocopy $stage $root /E /R:1 /W:1 /NFL /NDL /NP | Out-Null
if ($LASTEXITCODE -ge 8) { Fail "覆盖文件失败（robocopy 代码 $LASTEXITCODE）。" }
Remove-Item -Recurse -Force $stage -ErrorAction SilentlyContinue
Remove-InstallerSideEffects

$node = Join-Path $root 'resources\runtime\primary-runtime\dependencies\node\bin\node.exe'
if (Test-Path $node) {
  & $node (Join-Path $root 'resources\portable\patch.cjs')
  if ($LASTEXITCODE -ne 0) { Fail 'app.asar 便携补丁重新应用失败，应用可能失去便携性。' }
} else {
  Fail '找不到内置 node.exe，无法重新应用 app.asar 补丁。'
}

$verFile = Join-Path $root 'version'
$ver = (Get-Content $verFile -Raw -ErrorAction SilentlyContinue)
if ($ver) { $ver = $ver.Trim() }

Write-Host "[ok] 升级完成，当前版本：$ver" -ForegroundColor Green
Write-Host '     数据目录 Data\ 未改动。'
if (-not $NoRelaunch) {
  Write-Host '正在重新启动应用...'
  Start-Process -FilePath $exe -WorkingDirectory $root
}
exit 0
