# DSH-desktop-portable

DeepSeek Harness (dsh) 桌面版的**完全便携打包**。所有数据、缓存、下载都只写入程序目录内的 `Data\`，删掉整个文件夹即为干净卸载，注册表和用户目录不会留下任何东西。

便携化已直接注入应用本体（`resources\app.asar` 内的引导入口），不需要任何启动器。

## 下载

成品体积约 1 GB（解压后），超过 GitHub 仓库单文件 100 MB 的限制，因此**不在仓库里**，通过 Releases 分发：

👉 见本仓库的 [Releases](../../releases) 页面，下载 `dsh-desktop-portable-clean.7z`。

| 项目 | 说明 |
|---|---|
| 文件名 | `dsh-desktop-portable-clean.7z` |
| 压缩包大小 | 240.4 MiB |
| 解压后 | 约 1.0 GiB，9779 个文件 |
| 解压工具 | [7-Zip](https://www.7-zip.org/) 或 WinRAR / NanaZip |
| 校验 | 见 Release 说明中的 SHA-256 |

解压后得到 `dsh-desktop-portable\` 文件夹，直接双击其中的 `DeepSeek Harness.exe` 即可运行。

### 这个包是「干净包」

发布包里已经**移除了所有个人数据**，不含任何密钥、Cookie 或会话记录：

- `Data\AppData\` —— Electron userData（Chromium 缓存、Cookies、登录态、日志）
- `Data\Temp\` —— 临时文件
- `Data\bootstrap.log` —— 便携引导日志
- `Data\dsh-home\.credentials.yaml` —— 浏览器会话密钥
- `Data\dsh-home\.anonymous-user-id`
- `Data\dsh-home\sessions\` —— 会话记录
- `Data\dsh-home\storages\` —— 会话索引缓存

首次启动时这些内容会自动重新生成，因此这个包可以安全地公开分发、也不需要任何清理步骤。

## 日常使用

- **启动**：双击 `DeepSeek Harness.exe`。
- **升级**：应用内出现更新提示时直接点更新即可——升级流程被接管为「无残留升级」：下载官方安装包 → 合并进本文件夹（自动重新应用便携补丁）→ 应用自动重启，`Data\` 原样保留。也可以右键 [`upgrade.ps1`](upgrade.ps1) →「使用 PowerShell 运行」手动升级；已下载好官方安装包时加参数 `-InstallerPath 安装包路径`。
- **从原安装版迁移数据**：右键 [`import-from-original.ps1`](import-from-original.ps1) →「使用 PowerShell 运行」。它会从 `%USERPROFILE%\.dsh` 和 `%APPDATA%\@deepseek-ai\dsh-desktop` 把登录凭据、会话、浏览器数据复制进本包的 `Data\`。建议在开始使用便携版之前运行一次，并先关闭原版应用（原版运行时会锁住部分文件）。

## 目录结构

```
dsh-desktop-portable\
├─ DeepSeek Harness.exe …   应用本体（双击即用，可整体升级）
├─ resources\
│  ├─ app.asar              已打便携补丁的应用（升级后自动重新打补丁）
│  ├─ portable\             便携补丁源码 + patch.cjs（升级自愈用）
│  ├─ app-update.yml        应用内更新配置（保留 = 启用应用内升级）
│  └─ runtime\              内置 Node / Python / pnpm 运行时
├─ upgrade.ps1              升级脚本（应用内升级也调用它）
├─ import-from-original.ps1 从原安装版同步数据
├─ README-便携说明.md       随包的中文说明
└─ Data\                    ★ 全部运行数据都在这里（首次启动自动生成）
   ├─ dsh-home\             Harness 主目录（登录凭据、会话、配置、插件、模型缓存）
   ├─ AppData\Roaming\      Electron userData（Chromium 缓存、Cookies、日志）
   ├─ AppData\Local\        更新下载缓存、npm / pip 等默认缓存
   ├─ Temp\                 临时文件
   ├─ pnpm-store\、pnpm\    pnpm 仓库与全局目录
   ├─ home\                 git / ssh 等命令行工具的 HOME
   ├─ bootstrap.log         便携引导日志（使用后出现，可删）
   └─ updates\              升级下载的安装包（使用后出现，可随时清空）
```

## 隔离机制

| 层 | 做什么 | 隔离掉的外部位置 |
|---|---|---|
| app.asar 引导入口（`resources\portable\`） | 启动最早期把用户数据环境钉进 `Data\`：`DSH_HOME`、`APPDATA`、`LOCALAPPDATA`、`TEMP/TMP`、`HOME`、`PNPM_HOME`、`npm_config_store_dir`；`app.setPath('userData')`；钩住 `child_process` 拦截更新安装器；禁止注册 `dsh://` 协议键 | `~/.dsh`、真实 `%APPDATA%` / `%LOCALAPPDATA%` / `%TEMP%`、pnpm 默认仓库 |

## 本仓库包含什么

出于体积和隐私考虑，仓库**只保留**上游脚本与本说明，不包含应用二进制和运行数据：

- ✅ [`upgrade.ps1`](upgrade.ps1)、[`import-from-original.ps1`](import-from-original.ps1)、本说明、[`.gitignore`](.gitignore)
- ❌ 应用本体、`resources\`、`locales\` 及各类二进制 —— 见 Releases
- ❌ `Data\` —— 含个人数据，永不提交

## 许可

本仓库仅为便携化打包的分发页。DeepSeek Harness 本体、Electron、Chromium、Node.js、Python、LibreOffice 等组件归各自权利人所有，并随包附带各自的许可文件（`LICENSE.electron.txt`、`LICENSES.chromium.html`、`resources\...\licenses\`）。分发与使用请遵守对应组件的许可条款。
