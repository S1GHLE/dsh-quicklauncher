# ============================================================================
#  dsh-keepup.ps1  --  双击入口 dsh-keepup.cmd 的实际逻辑
#
#  两条运行路线，首次运行会问一次，之后记住：
#    源码模式：git clone + pnpm install + pnpm run build，更新走 git pull
#    NPM 模式：npm install @deepseek-ai/dsh，更新走 npm install @latest
#
#  两条路线共用：端口复用检测、更新提示菜单、跳过记忆、浏览器交接、结果摘要。
#
#  !! 本文件必须保存为 带 BOM 的 UTF-8 !!
#  Windows PowerShell 5.1 会把无 BOM 的脚本按系统 ANSI(GBK) 读，中文会变乱码
#  甚至语法报错。改完文件请确认编码没被编辑器改掉。
#
#  测试模式：
#    --smoke-version   打印检测结果（版本/模式/工具链/端口），不启动
#    --smoke-menu      用示例数据渲染更新提示
#    --smoke-install   用示例数据渲染安装选择菜单
#    --smoke-launch    打印解析出的启动命令
#    --smoke-run       走真实流程但不打开浏览器、不等待按键
#    --reset           删除保存的模式选择，下次重新询问
#  环境变量：
#    DSH_HOME / DSH_WEB_PORT / DSH_LAUNCHER_REPO / DSH_LAUNCHER_TOOLS
#    DSH_LAUNCHER_MODE=source|npm        DSH_LAUNCHER_SKIP_CHECK=1
# ============================================================================

# 注意：不要用 param() 接这个参数。Windows PowerShell 5.1 以 -File 启动时，
# 以 "--" 开头的参数不会被绑定到 param 块，只能从 $args 取。
$Mode = if ($args.Count -gt 0) { [string]$args[0] } else { '' }

# 控制台按 UTF-8 输出，否则中文在 GBK 控制台里会乱码
try { chcp 65001 > $null } catch { }
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
$OutputEncoding = [System.Text.Encoding]::UTF8

$SkipBrowser = ($Mode -eq '--smoke-run')
$NoPause     = ($Mode -eq '--smoke-run')

$Here       = Split-Path -Parent $MyInvocation.MyCommand.Path
# DSH_LAUNCHER_CONFIG 让测试可以用临时配置，不碰真实配置
$ConfigPath = if ($env:DSH_LAUNCHER_CONFIG) { $env:DSH_LAUNCHER_CONFIG } else { Join-Path $Here '.dsh-launch-config.json' }
$SkipFile   = Join-Path $Here '.dsh-launch-skip.txt'
$VERSION    = '2.0'

# ---------------------------------------------------------------- 目标常量 ---
$REPO_URL    = 'https://github.com/deepseek-ai/deepseek-harness.git'
$NPM_PACKAGE = '@deepseek-ai/dsh'
$NODE_RANGE  = '^22.19.0 或 >=24.0.0（不接受 Node 23）'

# ============================================================== 输出辅助 ======
function Write-Line {
    param([string]$Text = '', [string]$Kind = 'info')
    switch ($Kind) {
        'step'  { Write-Host ('  ..  ' + $Text) -ForegroundColor Cyan }
        'ok'    { Write-Host ('  OK  ' + $Text) -ForegroundColor Green }
        'warn'  { Write-Host ('  !!  ' + $Text) -ForegroundColor Yellow }
        'bad'   { Write-Host ('  XX  ' + $Text) -ForegroundColor Red }
        'head'  { Write-Host $Text -ForegroundColor White }
        'dim'   { Write-Host $Text -ForegroundColor DarkGray }
        default { Write-Host $Text }
    }
}
function Write-Rule { Write-Host ('  ' + ('-' * 68)) -ForegroundColor DarkGray }
function Write-Banner {
    Clear-Host
    Write-Host ''
    Write-Host '   DeepSeek Harness' -ForegroundColor Cyan
    Write-Host ('   一键启动入口 v' + $VERSION + '   ' + (Get-Date -Format 'yyyy-MM-dd HH:mm:ss')) -ForegroundColor DarkGray
    Write-Host ''
}
function Write-Summary {
    param($Notes)
    Write-Host ''
    Write-Rule
    Write-Line '本次结果' 'head'
    if (-not $Notes -or $Notes.Count -eq 0) { Write-Line '  一切正常，没有需要说明的事项。' 'dim' }
    foreach ($note in $Notes) { Write-Host ('  - ' + $note) }
    Write-Rule
    Write-Host ''
}
function Pause-IfNeeded {
    if (-not $NoPause) { Read-Host '按回车键关闭窗口' }
}

# ============================================================== 基础工具 ======
function Invoke-Capture {
    param([string]$Exe, [string[]]$Arguments, [string]$WorkDir)
    try {
        if ($WorkDir) {
            Push-Location $WorkDir
            $out = & $Exe @Arguments 2>&1
            Pop-Location
        } else {
            $out = & $Exe @Arguments 2>&1
        }
        return [pscustomobject]@{
            Exit   = $LASTEXITCODE
            Output = (($out | ForEach-Object { [string]$_ }) -join [Environment]::NewLine)
        }
    } catch {
        return [pscustomobject]@{ Exit = -1; Output = $_.Exception.Message }
    }
}

function Find-Command {
    param([string]$Name)
    $c = Get-Command $Name -ErrorAction SilentlyContinue
    if ($c) { return $c.Source }
    return $null
}

function Get-NodeVersion {
    $node = Find-Command 'node'
    if (-not $node) { return $null }
    $r = Invoke-Capture -Exe $node -Arguments @('--version')
    if ($r.Exit -ne 0) { return $null }
    return ([string]$r.Output).Trim()
}

# 解析并校验 engines.node：^22.19.0 || >=24.0.0
function Test-NodeVersion {
    param([string]$Version)
    if ([string]::IsNullOrWhiteSpace($Version)) { return $false }
    $v = $Version.TrimStart('v').Trim()
    $parts = $v -split '\.'
    if ($parts.Count -lt 2) { return $false }
    $major = 0; $minor = 0
    if (-not [int]::TryParse($parts[0], [ref]$major)) { return $false }
    if (-not [int]::TryParse($parts[1], [ref]$minor)) { return $false }
    if ($major -eq 22 -and $minor -ge 19) { return $true }
    if ($major -ge 24) { return $true }
    return $false
}

function Get-PortState {
    param([int]$Port)
    $client = $null
    try {
        $client = New-Object System.Net.Sockets.TcpClient
        $iar = $client.BeginConnect('127.0.0.1', $Port, $null, $null)
        if ($iar.AsyncWaitHandle.WaitOne(450, $false)) {
            $client.EndConnect($iar)
            if ($client.Connected) { return 'open' }
        }
        return 'closed'
    } catch {
        return 'closed'
    } finally {
        if ($client) { $client.Close() }
    }
}

function Open-DshBrowser {
    param([string]$Url)
    if ($SkipBrowser) { Write-Line ('[smoke-run] 本应打开: ' + $Url) 'dim'; return $true }
    try {
        Start-Process $Url | Out-Null
        Write-Line ('已用默认浏览器打开 ' + $Url) 'ok'
        return $true
    } catch {
        Write-Line ('无法自动打开浏览器：' + $_.Exception.Message) 'warn'
        Write-Line ('请手动访问：' + $Url) 'warn'
        return $false
    }
}

function Get-VersionFromPath {
    param([string]$Dir)
    if ([string]::IsNullOrWhiteSpace($Dir)) { return $null }
    $manifest = Join-Path $Dir 'package.json'
    if (-not (Test-Path -LiteralPath $manifest)) { return $null }
    try {
        $data = Get-Content -LiteralPath $manifest -Raw -Encoding UTF8 | ConvertFrom-Json
        if ($data.version) { return [string]$data.version }
    } catch { }
    return $null
}

# ============================================================== 交互菜单 ======
function Read-MenuChoice {
    param([int]$Count, [int]$Default)
    while ($true) {
        $raw = Read-Host '请输入序号后回车'
        if ([string]::IsNullOrWhiteSpace($raw)) { return $Default }
        $value = 0
        if ([int]::TryParse($raw.Trim(), [ref]$value) -and $value -ge 1 -and $value -le $Count) { return $value }
        Write-Host ('  请输入 1 - ' + $Count) -ForegroundColor Yellow
    }
}

# ============================================================== 配置读写 ======
function Read-LaunchConfig {
    $empty = [pscustomobject]@{ Mode = $null; RepoDir = $null; NpmDir = $null }
    if (-not (Test-Path -LiteralPath $ConfigPath)) { return $empty }
    try {
        $data = Get-Content -LiteralPath $ConfigPath -Raw -Encoding UTF8 | ConvertFrom-Json
        return [pscustomobject]@{
            Mode    = if ($data.mode)    { [string]$data.mode }    else { $null }
            RepoDir = if ($data.repoDir) { [string]$data.repoDir } else { $null }
            NpmDir  = if ($data.npmDir)  { [string]$data.npmDir }  else { $null }
        }
    } catch {
        Write-Line ('配置文件读取失败，已忽略：' + $_.Exception.Message) 'warn'
        return $empty
    }
}

function Save-LaunchConfig {
    param([string]$ModeValue, [string]$RepoDir, [string]$NpmDir)
    $payload = [ordered]@{
        version = $VERSION
        mode    = $ModeValue
        repoDir = $RepoDir
        npmDir  = $NpmDir
        savedAt = (Get-Date).ToString('s')
    }
    try {
        ($payload | ConvertTo-Json) | Set-Content -LiteralPath $ConfigPath -Encoding UTF8
        Write-Line ('已保存选择到 ' + (Split-Path $ConfigPath -Leaf)) 'ok'
    } catch {
        Write-Line ('无法保存配置：' + $_.Exception.Message) 'warn'
    }
}

# ============================================================== 路径发现 ======
# 参数名统一用 -Dir，并且都加 [Alias('Path')]：Windows PowerShell 对未知的
# 具名参数不会报错，只会静默地什么都不绑，导致函数体拿到空串而返回假结果。
# 加别名可以避免这种"改了参数名就静默失效"的坑。
function Test-SourceInstall {
    param([Alias('Path')][string]$Dir)
    if ([string]::IsNullOrWhiteSpace($Dir)) { return $false }
    if (-not (Test-Path -LiteralPath (Join-Path $Dir '.git'))) { return $false }
    if (-not (Test-Path -LiteralPath (Join-Path $Dir 'apps\cli\src\bin.ts'))) { return $false }
    return $true
}

function Test-NpmInstall {
    param([Alias('Path')][string]$Dir)
    if ([string]::IsNullOrWhiteSpace($Dir)) { return $false }
    return (Test-Path -LiteralPath (Join-Path $Dir 'node_modules\@deepseek-ai\dsh\lib\bin.js'))
}

# 按优先级找一个可用的源码 checkout
function Find-SourceDir {
    param($Saved)
    $candidates = New-Object System.Collections.Generic.List[string]

    if ($env:DSH_LAUNCHER_REPO) { $candidates.Add($env:DSH_LAUNCHER_REPO) }
    if ($Saved.RepoDir)         { $candidates.Add($Saved.RepoDir) }

    if ($env:DSH_LAUNCHER_NO_AUTODISCOVER -ne '1') {
        # 启动器所在目录及其祖先（兼容把启动器放进 checkout 里的用法）
        $cursor = $Here
        for ($i = 0; $i -lt 4 -and $cursor; $i++) {
            $candidates.Add((Join-Path $cursor 'deepseek-harness'))
            $candidates.Add($cursor)
            $parent = Split-Path -Parent $cursor
            if ($parent -eq $cursor -or [string]::IsNullOrWhiteSpace($parent)) { break }
            $cursor = $parent
        }

        $candidates.Add((Join-Path $env:USERPROFILE 'deepseek-harness'))

        # 本机历史路径也认，但只在它真的存在时才作为候选：写死的路径不该让别的
        # 机器去 clone 一份 1.5 GB 的源码。
        $legacy = 'F:\GitHubProject\deepseek-harness'
        if (Test-Path -LiteralPath $legacy) { $candidates.Add($legacy) }
    }

    foreach ($candidate in $candidates) {
        if (Test-SourceInstall -Path $candidate) { return $candidate }
    }
    return $null
}

function Get-DefaultNpmDir {
    if ($env:DSH_LAUNCHER_TOOLS) { return $env:DSH_LAUNCHER_TOOLS }
    return (Join-Path $Here 'tools\dsh-npm')
}

function Get-DefaultRepoDir {
    if ($env:DSH_LAUNCHER_REPO) { return $env:DSH_LAUNCHER_REPO }
    return (Join-Path $env:USERPROFILE 'deepseek-harness')
}

# ============================================================== 安装流程 ======
function Format-Size {
    param([double]$Bytes)
    if ($Bytes -ge 1GB) { return ('{0:N2} GB' -f ($Bytes / 1GB)) }
    if ($Bytes -ge 1MB) { return ('{0:N1} MB' -f ($Bytes / 1MB)) }
    return ('{0:N0} KB' -f ($Bytes / 1KB))
}

function Get-DirSize {
    param([string]$Dir)
    if (-not (Test-Path -LiteralPath $Dir)) { return 0 }
    try {
        $s = Get-ChildItem -LiteralPath $Dir -Recurse -File -Force -ErrorAction SilentlyContinue |
             Measure-Object -Property Length -Sum
        return [double]$s.Sum
    } catch { return 0 }
}

# 需要 pnpm 时：corepack 优先，失败则全局 npm 安装
function Install-Pnpm {
    Write-Line '未找到 pnpm，尝试自动安装 ...' 'step'
    $node = Find-Command 'node'
    if ($node) {
        $corepack = Join-Path (Split-Path $node -Parent) 'corepack.cmd'
        if (Test-Path -LiteralPath $corepack) {
            Write-Line '尝试 corepack enable ...' 'step'
            $r = Invoke-Capture -Exe $corepack -Arguments @('enable')
            if ($r.Exit -eq 0 -and (Find-Command 'pnpm')) {
                Write-Line 'corepack 已启用 pnpm' 'ok'
                return $true
            }
            Write-Line ('corepack 未成功：' + $r.Output) 'warn'
        }
    }
    $npm = Find-Command 'npm'
    if (-not $npm) {
        Write-Line 'npm 也不可用，无法自动安装 pnpm' 'bad'
        return $false
    }
    Write-Line '尝试 npm install -g pnpm ...' 'step'
    $r = Invoke-Capture -Exe $npm -Arguments @('install', '-g', 'pnpm', '--no-audit', '--no-fund')
    if ($r.Exit -eq 0 -and (Find-Command 'pnpm')) {
        Write-Line 'pnpm 安装完成' 'ok'
        return $true
    }
    Write-Line 'pnpm 自动安装失败' 'bad'
    Write-Line ('  输出：' + $r.Output) 'dim'
    Write-Line '  请手动装好后重跑：npm install -g pnpm' 'warn'
    return $false
}

function Install-SourceMode {
    param([string]$RepoDir)
    Write-Host ''
    Write-Rule
    Write-Line '源码模式安装' 'head'
    Write-Rule

    $git = Find-Command 'git'
    if (-not $git) {
        Write-Line '未找到 git，无法克隆源码。请先安装 Git for Windows。' 'bad'
        return $false
    }
    if (-not (Find-Command 'pnpm')) {
        if (-not (Install-Pnpm)) { return $false }
    }
    $pnpm = Find-Command 'pnpm'

    if (Test-SourceInstall -Path $RepoDir) {
        Write-Line ('已存在源码 checkout：' + $RepoDir) 'ok'
    } else {
        if (Test-Path -LiteralPath $RepoDir) {
            $entries = @(Get-ChildItem -LiteralPath $RepoDir -Force -ErrorAction SilentlyContinue)
            if ($entries.Count -gt 0) {
                Write-Line ('目标目录非空且不是 git checkout：' + $RepoDir) 'bad'
                Write-Line '请换一个目录（设 DSH_LAUNCHER_REPO 环境变量），或清空它。' 'warn'
                return $false
            }
        } else {
            $parent = Split-Path -Parent $RepoDir
            if ($parent -and -not (Test-Path -LiteralPath $parent)) { New-Item -ItemType Directory -Path $parent -Force | Out-Null }
        }
        Write-Line ('克隆 ' + $REPO_URL) 'step'
        Write-Line ('  -> ' + $RepoDir) 'dim'
        $r = Invoke-Capture -Exe $git -Arguments @('clone', '--depth', '1', $REPO_URL, $RepoDir)
        if ($r.Exit -ne 0) {
            Write-Line 'git clone 失败' 'bad'
            ($r.Output -split "`n" | Select-Object -Last 6) | ForEach-Object { Write-Line ('    ' + $_.Trim()) 'dim' }
            return $false
        }
        Write-Line '克隆完成' 'ok'
    }

    Write-Line '安装依赖（pnpm install，约 1.5 GB，需要几分钟）...' 'step'
    $r = Invoke-Capture -Exe $pnpm -Arguments @('install') -WorkDir $RepoDir
    if ($r.Exit -ne 0) {
        Write-Line 'pnpm install 失败' 'bad'
        ($r.Output -split "`n" | Select-Object -Last 8) | ForEach-Object { Write-Line ('    ' + $_.Trim()) 'dim' }
        return $false
    }
    Write-Line '依赖安装完成' 'ok'

    Write-Line '构建产物（pnpm run build，可能十几分钟）...' 'step'
    $r = Invoke-Capture -Exe $pnpm -Arguments @('run', 'build') -WorkDir $RepoDir
    if ($r.Exit -ne 0) {
        Write-Line 'pnpm run build 失败' 'bad'
        ($r.Output -split "`n" | Select-Object -Last 10) | ForEach-Object { Write-Line ('    ' + $_.Trim()) 'dim' }
        Write-Line '源码构建常需要 C++ 工具链（原生扩展），失败也正常。' 'warn'
        return $false
    }
    Write-Line '构建完成' 'ok'
    return $true
}

function Install-NpmMode {
    param([string]$NpmDir)
    Write-Host ''
    Write-Rule
    Write-Line 'NPM 模式安装' 'head'
    Write-Rule

    $npm = Find-Command 'npm'
    if (-not $npm) {
        Write-Line '未找到 npm，无法安装。请先安装 Node.js（自带 npm）。' 'bad'
        return $false
    }

    if (-not (Test-Path -LiteralPath $NpmDir)) {
        New-Item -ItemType Directory -Path $NpmDir -Force | Out-Null
    }
    $manifest = Join-Path $NpmDir 'package.json'
    if (-not (Test-Path -LiteralPath $manifest)) {
        Set-Content -LiteralPath $manifest -Value '{"name":"dsh-npm-toolchain","private":true,"version":"1.0.0"}' -Encoding ASCII
    }

    $installed = Get-VersionFromPath (Join-Path $NpmDir 'node_modules\@deepseek-ai\dsh')
    Write-Line ('安装 ' + $NPM_PACKAGE + ' 到 ' + $NpmDir) 'step'
    if ($installed) { Write-Line ('  当前已装版本：' + $installed) 'dim' }
    $r = Invoke-Capture -Exe $npm -Arguments @('install', ($NPM_PACKAGE + '@latest'), '--no-audit', '--no-fund', '--loglevel=error') -WorkDir $NpmDir
    if ($r.Exit -ne 0) {
        Write-Line 'npm install 失败' 'bad'
        ($r.Output -split "`n" | Select-Object -Last 8) | ForEach-Object { Write-Line ('    ' + $_.Trim()) 'dim' }
        return $false
    }

    $now = Get-VersionFromPath (Join-Path $NpmDir 'node_modules\@deepseek-ai\dsh')
    $size = Get-DirSize -Dir $NpmDir
    Write-Line ('安装完成，版本 ' + $now + '，占用 ' + (Format-Size -Bytes $size)) 'ok'
    return $true
}

# 首次运行：渲染菜单并返回 source / npm / quit
function Invoke-SetupMenu {
    param([string]$RepoDir, [string]$NpmDir)
    Write-Host ''
    Write-Rule
    Write-Line '首次运行：请选择运行方式' 'head'
    Write-Rule
    Write-Host ''
    Write-Host '  1) 源码模式（推荐开发者）'
    Write-Host '     git clone + pnpm install + pnpm run build'
    Write-Host ('     源码目录：' + $RepoDir) -ForegroundColor DarkGray
    Write-Host '     需要 git 和 pnpm；约 1.5 GB，首次构建十几分钟' -ForegroundColor DarkGray
    Write-Host '     更新方式：git pull，能看到每个提交' -ForegroundColor DarkGray
    Write-Host ''
    Write-Host '  2) NPM 模式（推荐只想用的人）'
    Write-Host ('     npm install ' + $NPM_PACKAGE)
    Write-Host ('     安装目录：' + $NpmDir) -ForegroundColor DarkGray
    Write-Host '     只需要 Node.js；约 214 MB，一分钟装完' -ForegroundColor DarkGray
    Write-Host '     更新方式：跟随 npm 发布版' -ForegroundColor DarkGray
    Write-Host ''
    Write-Host '  3) 退出'
    Write-Host ''

    $choice = Read-MenuChoice -Count 3 -Default 2
    switch ($choice) {
        1 { return 'source' }
        2 { return 'npm' }
        default { return 'quit' }
    }
}

# 源码安装失败后询问是否改走 NPM
function Confirm-NpmFallback {
    Write-Host ''
    Write-Line '源码路线没有成功。要改用 NPM 模式先把 DSH 跑起来吗？' 'warn'
    Write-Host '  1) 改用 NPM 模式（约 214 MB，一分钟）'
    Write-Host '  2) 不，退出'
    Write-Host ''
    $choice = Read-MenuChoice -Count 2 -Default 1
    return ($choice -eq 1)
}

# ============================================================== 启动命令 ======
function Resolve-BootCommand {
    param($Cfg)
    $node = Find-Command 'node'
    if (-not $node) { $node = 'node' }

    $webFlags = @()
    if ($Cfg.Port -ne 3080) { $webFlags += @('--port', [string]$Cfg.Port) }
    $webFlags += '--no-open'

    if ($Cfg.Mode -eq 'source') {
        $entry = Join-Path $Cfg.RepoDir 'apps\cli\src\bin.ts'
        return [pscustomobject]@{
            File    = $node
            Args    = @('--import', 'tsx/esm', $entry, 'web') + $webFlags
            WorkDir = $Cfg.RepoDir
            Display = ('node --import tsx/esm "' + $entry + '" web ' + ($webFlags -join ' '))
        }
    }

    $entry = Join-Path $Cfg.NpmDir 'node_modules\@deepseek-ai\dsh\lib\bin.js'
    return [pscustomobject]@{
        File    = $node
        Args    = @($entry, 'web') + $webFlags
        WorkDir = $Cfg.RepoDir
        Display = ('node "' + $entry + '" web ' + ($webFlags -join ' '))
    }
}

function Start-DshWindow {
    param($Cfg, $Boot)
    $env:DSH_HOME = $Cfg.Home
    Start-Process -FilePath $Boot.File -ArgumentList $Boot.Args `
                  -WorkingDirectory $Boot.WorkDir -WindowStyle Normal | Out-Null
    return $true
}

# ============================================================== 更新检查 ======
function Get-NpmLatest {
    param($Cfg)
    if (-not $Cfg.NpmSource) { return @{ Status = 'disabled'; Version = $null; Error = $null } }
    # 用 node 的 fetch：本机 PowerShell 5.1 的 HTTPS 栈连不上，而 node 也认代理变量
    $script = @'
const url = "https://registry.npmjs.org/@deepseek-ai%2Fdsh";
fetch(url, { headers: { accept: "application/vnd.npm.install-v1+json" } })
  .then(function (r) { return r.json(); })
  .then(function (j) {
    var tags = (j && j["dist-tags"]) || {};
    var version = tags.latest || j.version || "";
    if (version) { console.log("OK " + version); }
    else { console.log("ERR registry returned no latest tag"); }
  })
  .catch(function (e) { console.log("ERR " + (e && e.message ? e.message : String(e))); });
'@
    $probe = Join-Path $env:TEMP ('dsh-npm-latest-' + [Guid]::NewGuid().ToString('N') + '.mjs')
    try {
        Set-Content -LiteralPath $probe -Value $script -Encoding ASCII
        $node = Find-Command 'node'
        if (-not $node) { return @{ Status = 'unavailable'; Version = $null; Error = 'node 未找到' } }
        $raw = (& $node $probe 2>&1 | Out-String).Trim()
        if ($raw -match '^OK\s+(\S+)') { return @{ Status = 'ok'; Version = $Matches[1]; Error = $null } }
        $detail = ($raw -replace '^ERR\s*', '').Trim()
        if ([string]::IsNullOrWhiteSpace($detail)) { $detail = 'node 没有输出' }
        if ($detail.Length -gt 200) { $detail = $detail.Substring(0, 200) + '...' }
        return @{ Status = 'unavailable'; Version = $null; Error = $detail }
    } catch {
        return @{ Status = 'unavailable'; Version = $null; Error = $_.Exception.Message }
    } finally {
        try { if (Test-Path -LiteralPath $probe) { Remove-Item -LiteralPath $probe -Force } } catch { }
    }
}

function Get-GitUpdate {
    param([string]$RepoDir)
    $result = [ordered]@{
        Available = $false; Checked = $false; Reason = $null
        Branch = $null; LocalSha = $null; RemoteSha = $null; Behind = 0; Subjects = @()
    }
    $git = Find-Command 'git'
    if (-not $git) { $result.Reason = 'git 未找到，无法检查源码更新'; return [pscustomobject]$result }
    try {
        $branch = (& $git -C $RepoDir rev-parse --abbrev-ref HEAD 2>$null)
        if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrWhiteSpace($branch)) {
            $result.Reason = 'git 仓库处于 detached HEAD，无法比对分支'
            return [pscustomobject]$result
        }
        $result.Branch   = ([string]$branch).Trim()
        $result.LocalSha = ([string](& $git -C $RepoDir rev-parse --short HEAD 2>$null)).Trim()

        $env:GIT_TERMINAL_PROMPT = '0'
        $fetchLog = (& $git -C $RepoDir fetch --quiet --no-tags origin $result.Branch 2>&1)
        if ($LASTEXITCODE -ne 0) {
            $detail = ([string]($fetchLog -join ' ')).Trim()
            if ($detail.Length -gt 240) { $detail = $detail.Substring(0, 240) + '...' }
            $result.Reason = 'git fetch 失败：' + $detail
            return [pscustomobject]$result
        }
        $result.RemoteSha = ([string](& $git -C $RepoDir rev-parse --short FETCH_HEAD 2>$null)).Trim()

        $count = (& $git -C $RepoDir rev-list --count 'HEAD..FETCH_HEAD' 2>$null)
        if ($LASTEXITCODE -ne 0) {
            $result.Reason = 'git rev-list 失败，无法判断是否落后'
            return [pscustomobject]$result
        }
        $result.Checked = $true
        if ($count) { $result.Behind = [int]$count }
        if ($result.Behind -gt 0) {
            $result.Available = $true
            $subjects = & $git -C $RepoDir log --pretty=format:'%h %s' --no-merges 'HEAD..FETCH_HEAD' 2>$null
            $result.Subjects = @($subjects | Select-Object -First 8)
        }
        return [pscustomobject]$result
    } catch {
        $result.Reason = 'git 检查出错：' + $_.Exception.Message
        return [pscustomobject]$result
    }
}

# ============================================================== 跳过记忆 ======
function Get-SkipKey {
    param($Npm, $GitState)
    $parts = @()
    if ($Npm -and $Npm.Status -eq 'ok' -and $Npm.Version) { $parts += ('npm=' + $Npm.Version) }
    if ($GitState -and $GitState.Available -and $GitState.RemoteSha) { $parts += ('git=' + $GitState.RemoteSha) }
    return ($parts -join ';')
}
function Read-SkipKey {
    try {
        if (Test-Path -LiteralPath $SkipFile) { return ([string](Get-Content -LiteralPath $SkipFile -Raw -Encoding UTF8)).Trim() }
    } catch { }
    return ''
}
function Write-SkipKey { param([string]$Key) try { Set-Content -LiteralPath $SkipFile -Value $Key -Encoding UTF8 } catch { } }
function Clear-SkipKey { try { if (Test-Path -LiteralPath $SkipFile) { Remove-Item -LiteralPath $SkipFile -Force } } catch { } }

# ============================================================== 更新执行 ======
function Invoke-SourceUpdate {
    param([string]$RepoDir, [string]$ExpectedSha)
    $git  = Find-Command 'git'
    $pnpm = Find-Command 'pnpm'
    if (-not $git)  { Write-Line 'git 未找到，无法更新' 'bad'; return $false }
    if (-not $pnpm) { Write-Line 'pnpm 未找到，无法同步依赖和构建' 'bad'; return $false }

    Write-Host ''
    Write-Rule
    Write-Line '开始更新源码' 'head'
    Write-Rule

    $status = & $git -C $RepoDir status --porcelain 2>$null
    if ($LASTEXITCODE -eq 0 -and $status) {
        Write-Line '工作区有未提交的本地改动，为安全起见已跳过自动更新。' 'warn'
        Write-Line ('请先处理：git -C "' + $RepoDir + '" status') 'warn'
        return $false
    }

    $before = ([string](& $git -C $RepoDir rev-parse HEAD 2>$null)).Trim()
    $branch = ([string](& $git -C $RepoDir rev-parse --abbrev-ref HEAD 2>$null)).Trim()
    if ([string]::IsNullOrWhiteSpace($branch)) { $branch = 'master' }

    Write-Line ('拉取 origin/' + $branch + ' ...') 'step'
    $pullLog = (& $git -C $RepoDir merge --ff-only ('origin/' + $branch) 2>&1)
    if ($LASTEXITCODE -ne 0) {
        Write-Line '快进合并失败（本地与远端可能已分叉）' 'bad'
        ($pullLog | Select-Object -Last 6) | ForEach-Object { Write-Line ('    ' + $_) 'dim' }
        return $false
    }
    $after      = ([string](& $git -C $RepoDir rev-parse HEAD 2>$null)).Trim()
    $shortAfter = ([string](& $git -C $RepoDir rev-parse --short HEAD 2>$null)).Trim()
    Write-Line ('代码已更新到 ' + $shortAfter) 'ok'

    Write-Line '同步依赖（pnpm install）...' 'step'
    $r = Invoke-Capture -Exe $pnpm -Arguments @('install') -WorkDir $RepoDir
    if ($r.Exit -ne 0) {
        Write-Line 'pnpm install 失败，已中止更新' 'bad'
        ($r.Output -split "`n" | Select-Object -Last 8) | ForEach-Object { Write-Line ('    ' + $_.Trim()) 'dim' }
        return $false
    }
    Write-Line '依赖已同步' 'ok'

    if ($before -ne $after) {
        Write-Line '重新构建产物（可能十几分钟，请勿关闭窗口）...' 'step'
        $r = Invoke-Capture -Exe $pnpm -Arguments @('run', 'build') -WorkDir $RepoDir
        if ($r.Exit -ne 0) {
            Write-Line '构建失败。代码已更新，但产物可能不完整。' 'bad'
            ($r.Output -split "`n" | Select-Object -Last 10) | ForEach-Object { Write-Line ('    ' + $_.Trim()) 'dim' }
            return $false
        }
        Write-Line '构建完成' 'ok'
    } else {
        Write-Line '本次没有代码变化，跳过构建' 'ok'
    }

    Clear-SkipKey
    if ($ExpectedSha -and $shortAfter -and ($shortAfter -ne $ExpectedSha)) {
        Write-Line ('注意：远端 HEAD 已从 ' + $ExpectedSha + ' 前进到 ' + $shortAfter) 'warn'
    }
    return $true
}

function Invoke-NpmUpdate {
    param([string]$NpmDir, [string]$TargetVersion)
    Write-Host ''
    Write-Rule
    Write-Line '开始更新 NPM 包' 'head'
    Write-Rule
    $npmTool = Find-Command 'npm'
    if (-not $npmTool) { Write-Line 'npm 未找到，无法更新' 'bad'; return $false }

    Write-Line ('安装 ' + $NPM_PACKAGE + '@latest ...') 'step'
    $r = Invoke-Capture -Exe $npmTool -Arguments @('install', ($NPM_PACKAGE + '@latest'), '--no-audit', '--no-fund', '--loglevel=error') -WorkDir $NpmDir
    if ($r.Exit -ne 0) {
        Write-Line 'npm install 失败' 'bad'
        ($r.Output -split "`n" | Select-Object -Last 8) | ForEach-Object { Write-Line ('    ' + $_.Trim()) 'dim' }
        return $false
    }
    $now = Get-VersionFromPath (Join-Path $NpmDir 'node_modules\@deepseek-ai\dsh')
    Write-Line ('已更新到 ' + $now) 'ok'
    if ($TargetVersion -and $now -and $now -ne $TargetVersion) {
        Write-Line ('注意：装出来的是 ' + $now + '，registry 报的是 ' + $TargetVersion) 'warn'
    }
    Clear-SkipKey
    return $true
}

# ============================================================== 更新菜单 ======
function Show-UpdatePrompt {
    param($Cfg, $Npm, $GitState, [string]$CurrentVersion)

    Write-Host ''
    Write-Rule
    Write-Line '检测到 DeepSeek Harness 有可用更新' 'head'
    Write-Rule
    Write-Host ('  运行方式   : ' + $(if ($Cfg.Mode -eq 'source') { '源码模式' } else { 'NPM 模式' }))
    Write-Host ('  当前版本   : ' + $CurrentVersion)
    if ($Cfg.Mode -eq 'source') {
        Write-Host ('  当前提交   : ' + $GitState.LocalSha + '  (' + $GitState.Branch + ')')
        Write-Host ''
        if ($GitState.Behind -gt 0) {
            Write-Host ('  git 源码   : 落后远端 ' + $GitState.Behind + ' 个提交  ->  ' + $GitState.RemoteSha) -ForegroundColor Yellow
            foreach ($subject in $GitState.Subjects) { Write-Host ('      ' + $subject) -ForegroundColor DarkGray }
        }
        if ($Npm -and $Npm.Status -eq 'ok' -and $Npm.Version -and $Npm.Version -ne $CurrentVersion) {
            Write-Host ('  npm 发布版 : ' + $Npm.Version + '（本地源码版本为 ' + $CurrentVersion + '）') -ForegroundColor DarkGray
        }
    } else {
        Write-Host ('  最新发布版 : ' + $Npm.Version) -ForegroundColor Yellow
    }
    Write-Rule
    Write-Host ''
    if ($Cfg.Mode -eq 'source') {
        Write-Host '  1) 立即更新（git pull + pnpm install + 重新构建）'
    } else {
        Write-Host '  1) 立即更新（npm install @latest）'
    }
    Write-Host '  2) 暂不更新，直接启动当前版本'
    Write-Host ''
    if ($Cfg.Mode -eq 'source') {
        Write-Line '  提示：更新需要重新构建产物，可能持续十几分钟；期间请勿关闭本窗口。' 'dim'
    }
    Write-Host ''

    $choice = Read-MenuChoice -Count 2 -Default 1
    if ($choice -eq 1) { return 'update' }
    return 'skip'
}

# ============================================================== 工具链检查 ======
function Test-Toolchain {
    param($Cfg)
    $nodeVersion = Get-NodeVersion
    if (-not $nodeVersion) {
        Write-Line ('未找到 Node.js。请先安装 Node.js（要求 ' + $NODE_RANGE + '）。') 'bad'
        return $false
    }
    if (-not (Test-NodeVersion -Version $nodeVersion)) {
        Write-Line ('Node 版本不满足要求：当前 ' + $nodeVersion + '，要求 ' + $NODE_RANGE) 'bad'
        return $false
    }
    if ($Cfg.Mode -eq 'source') {
        if (-not (Find-Command 'git')) {
            Write-Line '源码模式需要 git，但未找到。请安装 Git for Windows。' 'bad'
            return $false
        }
        if (-not (Find-Command 'pnpm')) {
            if (-not (Install-Pnpm)) { return $false }
        }
    }
    return $true
}

# ============================================================== 主流程 ======
Write-Banner
$notes = New-Object System.Collections.Generic.List[string]

if ($env:DSH_WEB_PORT -and $env:DSH_WEB_PORT -match '^\d+$') { $Port = [int]$env:DSH_WEB_PORT } else { $Port = 3080 }
$BindHost = '127.0.0.1'
$DshHome  = if ($env:DSH_HOME) { $env:DSH_HOME } else { Join-Path $env:USERPROFILE '.dsh' }

# --- 0. --reset ---
if ($Mode -eq '--reset') {
    if (Test-Path -LiteralPath $ConfigPath) {
        Remove-Item -LiteralPath $ConfigPath -Force
        Write-Line '已删除保存的模式选择，下次运行会重新询问。' 'ok'
    } else {
        Write-Line '没有保存过模式选择。' 'dim'
    }
    exit 0
}

$isSmoke = ($Mode -in @('--smoke-version', '--smoke-menu', '--smoke-install', '--smoke-launch'))

# --- 1. 端口复用检测 ---
if (-not $isSmoke) {
    if ((Get-PortState -Port $Port) -eq 'open') {
        $url = 'http://' + $BindHost + ':' + $Port + '/'
        Write-Line ('检测到 DSH 已在 ' + $url + ' 运行，不再启动第二个实例。') 'ok'
        Open-DshBrowser -Url $url | Out-Null
        $notes.Add('DSH 已经在运行，本次只打开了浏览器。')
        Write-Summary $notes
        Pause-IfNeeded
        exit 0
    }
}

# --- 2. 解析运行模式 ---
$saved   = Read-LaunchConfig
$npmDir  = if ($saved.NpmDir)  { $saved.NpmDir }  else { Get-DefaultNpmDir }
$repoDir = if ($saved.RepoDir) { $saved.RepoDir } else { Get-DefaultRepoDir }
$sourceDir = Find-SourceDir -Saved $saved

$chosenMode = $null
if ($env:DSH_LAUNCHER_MODE -in @('source', 'npm')) {
    $chosenMode = $env:DSH_LAUNCHER_MODE
    Write-Line ('运行模式由 DSH_LAUNCHER_MODE 指定：' + $chosenMode) 'dim'
} elseif ($saved.Mode) {
    $chosenMode = $saved.Mode
}

if ($chosenMode) {
    if ($chosenMode -eq 'source') {
        if (-not (Test-SourceInstall -Path $repoDir)) {
            if ($sourceDir) { $repoDir = $sourceDir }
            else {
                Write-Line ('配置的源码目录已失效：' + $repoDir) 'warn'
                $chosenMode = $null
            }
        }
    } elseif (-not (Test-NpmInstall -Path $npmDir)) {
        Write-Line ('配置的 NPM 目录尚未安装：' + $npmDir) 'warn'
        $chosenMode = $null
    }
}

# 没存过配置时，先看有没有现成的源码 checkout 或 NPM 安装
if (-not $chosenMode) {
    if ($sourceDir) {
        $chosenMode = 'source'
        if (-not $saved.RepoDir) { $repoDir = $sourceDir }
        Write-Line ('自动发现源码 checkout：' + $repoDir) 'ok'
    } elseif (Test-NpmInstall -Path $npmDir) {
        $chosenMode = 'npm'
        Write-Line ('自动发现 NPM 安装：' + $npmDir) 'ok'
    }
}

# --- 3. 首次运行：选择并安装 ---
if (-not $chosenMode) {
    if ($Mode -eq '--smoke-install') {
        Write-Banner
        Write-Host ('pick=' + (Invoke-SetupMenu -RepoDir $repoDir -NpmDir $npmDir))
        exit 0
    }
    # 其余 smoke 模式一律不装东西：装下去会真的改盘，测试不该有副作用。
    if ($isSmoke) {
        Write-Line ('[smoke] 目标安装不可用（mode=' + $saved.Mode + '），跳过安装步骤。') 'warn'
        Write-Host ('repoDir    = ' + $repoDir)
        Write-Host ('repoIsSource = ' + (Test-SourceInstall -Path $repoDir))
        Write-Host ('npmDir     = ' + $npmDir)
        Write-Host ('npmInstalled = ' + (Test-NpmInstall -Path $npmDir))
        exit 0
    }
    Write-Line '没有找到可用的 DSH 安装，需要先安装。' 'warn'
    $pick = Invoke-SetupMenu -RepoDir $repoDir -NpmDir $npmDir

    if ($pick -eq 'quit') { Write-Line '已取消。' 'dim'; exit 0 }

    if ($pick -eq 'source') {
        if (Install-SourceMode -RepoDir $repoDir) {
            $chosenMode = 'source'
        } elseif (Confirm-NpmFallback) {
            if (Install-NpmMode -NpmDir $npmDir) {
                $chosenMode = 'npm'
                $notes.Add('源码安装未成功，已按你的选择改用 NPM 模式。')
            } else {
                Write-Line 'NPM 安装也失败了，请检查网络后重试。' 'bad'
                Write-Summary $notes
                Pause-IfNeeded
                exit 1
            }
        } else {
            Write-Line '已取消。' 'dim'
            exit 0
        }
    } else {
        if (Install-NpmMode -NpmDir $npmDir) {
            $chosenMode = 'npm'
        } else {
            Write-Line 'NPM 安装失败，请检查网络后重试。' 'bad'
            Write-Summary $notes
            Pause-IfNeeded
            exit 1
        }
    }
    Save-LaunchConfig -ModeValue $chosenMode -RepoDir $repoDir -NpmDir $npmDir
    $notes.Add('首次安装完成，已记住运行方式（下次不再询问）。')
}

# --- 4. 组装配置 ---
$Cfg = [pscustomobject]@{
    Mode      = $chosenMode
    RepoDir   = $repoDir
    NpmDir    = $npmDir
    Home      = $DshHome
    Port      = $Port
    Host      = $BindHost
    NpmSource = $true
    GitSource = ($chosenMode -eq 'source')
}

# 启动需要有一个存在的工作目录；NPM 模式没有源码时退回用户目录
if (-not (Test-Path -LiteralPath $Cfg.RepoDir)) { $Cfg.RepoDir = $env:USERPROFILE }

# --- 5. 工具链检查 ---
if (-not (Test-Toolchain -Cfg $Cfg)) {
    Write-Summary $notes
    Pause-IfNeeded
    exit 1
}

$nodeVersion = Get-NodeVersion
if ($Cfg.Mode -eq 'source') {
    $currentVersion = Get-VersionFromPath (Join-Path $Cfg.RepoDir 'apps\cli')
} else {
    $currentVersion = Get-VersionFromPath (Join-Path $Cfg.NpmDir 'node_modules\@deepseek-ai\dsh')
}

# --- 6. smoke 模式 ---
if ($Mode -eq '--smoke-version') {
    Write-Host ('launcher      = v' + $VERSION)
    Write-Host ('mode          = ' + $Cfg.Mode)
    Write-Host ('node          = ' + $nodeVersion + '  ok=' + (Test-NodeVersion -Version $nodeVersion))
    Write-Host ('nodeRange     = ' + $NODE_RANGE)
    Write-Host ('repoDir       = ' + $Cfg.RepoDir)
    Write-Host ('repoIsSource  = ' + (Test-SourceInstall -Path $Cfg.RepoDir))
    Write-Host ('npmDir        = ' + $Cfg.NpmDir)
    Write-Host ('npmInstalled  = ' + (Test-NpmInstall -Path $Cfg.NpmDir))
    Write-Host ('version       = ' + $currentVersion)
    Write-Host ('dshHome       = ' + $Cfg.Home)
    Write-Host ('git           = ' + (Find-Command 'git'))
    Write-Host ('pnpm          = ' + (Find-Command 'pnpm'))
    Write-Host ('port          = ' + $Cfg.Port + ' state=' + (Get-PortState -Port $Cfg.Port))
    Write-Host ('configFile    = ' + $ConfigPath + ' exists=' + (Test-Path -LiteralPath $ConfigPath))
    if ($Cfg.Mode -eq 'source') {
        $gitState = Get-GitUpdate -RepoDir $Cfg.RepoDir
        Write-Host ('gitBehind     = ' + $gitState.Behind + ' checked=' + $gitState.Checked)
        if ($gitState.Reason) { Write-Host ('gitReason     = ' + $gitState.Reason) }
    }
    $row = Get-NpmLatest -Cfg $Cfg
    Write-Host ('npmStatus     = ' + $row.Status)
    Write-Host ('npmLatest     = ' + $row.Version)
    if ($row.Error) { Write-Host ('npmError      = ' + $row.Error) }
    Write-Host ('boot          = ' + (Resolve-BootCommand -Cfg $Cfg).Display)
    exit 0
}

if ($Mode -eq '--smoke-menu') {
    Write-Banner
    if ($Cfg.Mode -eq 'source') {
        $gitState = [pscustomobject]@{
            Available = $true; Checked = $true; Branch = 'master'; LocalSha = 'aa8262e'
            RemoteSha = 'bb12345'; Behind = 3
            Subjects = @('bb12345 feat: 示例提交一', 'cc99999 fix: 示例提交二')
        }
    } else {
        $gitState = [pscustomobject]@{
            Available = $false; Checked = $false; Branch = $null; LocalSha = $null
            RemoteSha = $null; Behind = 0; Subjects = @()
        }
    }
    $npm = @{ Status = 'ok'; Version = '0.1.6' }
    Write-Host ('choice=' + (Show-UpdatePrompt -Cfg $Cfg -Npm $npm -GitState $gitState -CurrentVersion $currentVersion))
    exit 0
}

if ($Mode -eq '--smoke-launch') {
    $boot = Resolve-BootCommand -Cfg $Cfg
    Write-Host ('file    = ' + $boot.File)
    Write-Host ('args    = ' + ($boot.Args -join ' | '))
    Write-Host ('workDir = ' + $boot.WorkDir)
    Write-Host ('display = ' + $boot.Display)
    exit 0
}

# --- 7. 更新检查 ---
if ($env:DSH_LAUNCHER_SKIP_CHECK -eq '1') {
    Write-Line 'DSH_LAUNCHER_SKIP_CHECK=1：已跳过更新检查。' 'warn'
    $notes.Add('按 DSH_LAUNCHER_SKIP_CHECK=1 跳过了更新检查。')
} else {
    $modeLabel = if ($Cfg.Mode -eq 'source') { '源码模式' } else { 'NPM 模式' }
    Write-Line ('正在检查更新（' + $modeLabel + '）...') 'step'

    $npm = Get-NpmLatest -Cfg $Cfg
    if ($npm.Status -eq 'ok') {
        Write-Line ('npm 发布版 latest：' + $npm.Version) 'ok'
    } elseif ($npm.Status -eq 'unavailable') {
        Write-Line ('npm 查询失败：' + $npm.Error) 'warn'
        $notes.Add('npm 更新检查失败（可能没网络或没配代理）。')
    }

    if ($Cfg.Mode -eq 'source') {
        $gitState = Get-GitUpdate -RepoDir $Cfg.RepoDir
        if ($gitState.Reason) { Write-Line $gitState.Reason 'warn' }
        if ($gitState.Available) {
            Write-Line ('git 源码落后远端 ' + $gitState.Behind + ' 个提交') 'warn'
        } elseif ($gitState.Checked) {
            Write-Line 'git 源码已是最新' 'ok'
        } else {
            Write-Line 'git 无法与远端比对，结果未知' 'warn'
        }
        $hasUpdate     = $gitState.Available
        $allChecked    = $gitState.Checked
        $targetVersion = $gitState.RemoteSha
    } else {
        $gitState = [pscustomobject]@{
            Available = $false; Checked = $false; Branch = $null; LocalSha = $null
            RemoteSha = $null; Behind = 0; Subjects = @()
        }
        $hasUpdate     = ($npm.Status -eq 'ok' -and $npm.Version -and $npm.Version -ne $currentVersion)
        $allChecked    = ($npm.Status -eq 'ok')
        $targetVersion = $npm.Version
    }

    if ($hasUpdate) {
        $key     = Get-SkipKey -Npm $npm -GitState $gitState
        $skipped = Read-SkipKey
        if ($key -and $skipped -eq $key) {
            Write-Line '这个更新你上次选择了"暂不更新"，本次直接启动。' 'warn'
            $notes.Add('该更新已被你跳过；删除 .dsh-launch-skip.txt 可恢复提示。')
        } else {
            $choice = Show-UpdatePrompt -Cfg $Cfg -Npm $npm -GitState $gitState -CurrentVersion $currentVersion
            if ($choice -eq 'update') {
                if ($Cfg.Mode -eq 'source') {
                    $done = Invoke-SourceUpdate -RepoDir $Cfg.RepoDir -ExpectedSha $targetVersion
                } else {
                    $done = Invoke-NpmUpdate -NpmDir $Cfg.NpmDir -TargetVersion $targetVersion
                }
                if ($done) {
                    if ($Cfg.Mode -eq 'source') {
                        $currentVersion = Get-VersionFromPath (Join-Path $Cfg.RepoDir 'apps\cli')
                    } else {
                        $currentVersion = Get-VersionFromPath (Join-Path $Cfg.NpmDir 'node_modules\@deepseek-ai\dsh')
                    }
                    $notes.Add('更新已完成，本次启动的是新版本。')
                } else {
                    Write-Line '更新没有完成，将以当前版本启动。' 'warn'
                    $notes.Add('更新没有完成，本次仍启动原有版本。')
                }
            } else {
                if ($key) { Write-SkipKey -Key $key }
                Write-Line '已选择暂不更新，本次启动当前版本。' 'warn'
                $notes.Add('你选择了暂不更新，已记住该选择，直到出现新的更新。')
            }
        }
    } elseif ($allChecked) {
        Write-Line '当前已是最新版本。' 'ok'
    } else {
        Write-Line '没有发现更新，但至少一项检查没能完成。' 'warn'
        $notes.Add('更新检查不完整（没网络或远端不通），已照常启动。')
    }
}

# --- 8. 启动 ---
$boot = Resolve-BootCommand -Cfg $Cfg
Write-Host ''
Write-Rule
Write-Line '启动 DSH ...' 'head'
Write-Line ('运行方式  : ' + $(if ($Cfg.Mode -eq 'source') { '源码模式' } else { 'NPM 模式' }) + '  版本 ' + $currentVersion) 'dim'
Write-Line ('DSH_HOME  : ' + $Cfg.Home) 'dim'
if ($Cfg.Mode -eq 'source') { Write-Line ('源码目录  : ' + $Cfg.RepoDir) 'dim' }
else { Write-Line ('NPM 目录  : ' + $Cfg.NpmDir) 'dim' }
Write-Line ('启动命令  : ' + $boot.Display) 'dim'
Write-Rule
Write-Host ''

$started = $false
try {
    Start-DshWindow -Cfg $Cfg -Boot $boot | Out-Null
    $started = $true
} catch {
    Write-Line ('启动失败：' + $_.Exception.Message) 'bad'
    $notes.Add('启动失败：' + $_.Exception.Message)
}

if ($started) {
    Write-Line '等待服务就绪（最多 120 秒）...' 'step'
    $ready = $false
    for ($i = 0; $i -lt 120; $i++) {
        Start-Sleep -Seconds 1
        if ((Get-PortState -Port $Cfg.Port) -eq 'open') { $ready = $true; break }
    }
    if ($ready) {
        $url = 'http://' + $Cfg.Host + ':' + $Cfg.Port + '/'
        Write-Line ('服务已就绪：' + $url) 'ok'
        Open-DshBrowser -Url $url | Out-Null
    } else {
        Write-Line '等待超时，服务可能仍在启动；请查看新打开的 DSH 窗口。' 'warn'
        $notes.Add('等待服务就绪超时，请查看 DSH 窗口。')
    }
}

Write-Summary $notes
Write-Host '  DSH 在单独的窗口中运行；关闭那个窗口即可停止服务。' -ForegroundColor DarkGray
Write-Host ''
Pause-IfNeeded
exit 0
