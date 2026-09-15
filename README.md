<p align="center">
  <img src="assets/dsh-icon.png" width="88" height="88" alt="dsh-quicklauncher 图标">
</p>

<h1 align="center">dsh-quicklauncher</h1>

<p align="center">
  <strong>双击启动 DSH，有更新时顺手更新。</strong><br>
  适用于 Windows 的 DeepSeek Harness 社区启动器
</p>

<p align="center">
  <a href="#快速开始">快速开始</a> ·
  <a href="#启动与更新">启动与更新</a> ·
  <a href="#常见问题">常见问题</a> ·
  <a href="#进阶配置">进阶配置</a>
</p>

把安装、更新检查和 Web 界面启动放进同一个入口。第一次运行按提示完成安装，以后双击 `.cmd` 文件或桌面快捷方式即可使用。

- **两种安装方式**：使用 npm 发布版，或从源码安装并构建。
- **启动前检查更新**：展示版本或提交信息，由你选择是否更新。
- **记住跳过的更新**：检测到的更新信息不变时，下次直接启动。
- **自动打开浏览器**：启动服务后等待本地端口可用，再打开 Web 界面。

> 本项目由社区维护，与 DeepSeek 官方无隶属关系，也未获官方背书。

## 快速开始

### 1. 准备环境

| 环境 | 要求 |
| --- | --- |
| 系统 | Windows，使用 Windows PowerShell 5.1 即可 |
| Node.js | 按当前启动器的校验规则：`^22.19.0` 或 `>=24.0.0`，不接受 Node.js 23 |
| npm | NPM 模式需要；通常随 Node.js 一起安装 |
| Git、pnpm | 源码模式需要；未找到 pnpm 时，启动器会尝试自动安装 |

首次安装和更新需要联网。相关命令应能在终端中直接运行。

### 2. 下载并双击

从[本仓库](https://github.com/S1GHLE/dsh-quicklauncher)选择 **Code → Download ZIP**，解压到一个固定目录；也可以克隆仓库：

```powershell
git clone https://github.com/S1GHLE/dsh-quicklauncher.git
```

打开文件夹，双击 **`dsh-quicklauncher.cmd`**。

请保留完整目录，尤其是同级的 `.cmd` 和 `.ps1` 文件。建议把启动器与 DSH 源码分别放在独立目录中。

### 3. 选择运行方式

没有检测到可用安装时，启动器会显示安装菜单：

| 选择 | 适合谁 | 首次运行会做什么 | 后续更新来源 |
| --- | --- | --- | --- |
| **2 · NPM 模式** | 日常使用 DSH 的用户 | 在启动器的本地工具目录安装 `@deepseek-ai/dsh` | npm 的 `latest` 发布版 |
| **1 · 源码模式** | 需要跟进源码或修改代码的开发者 | 克隆仓库、安装依赖、构建项目 | 当前分支对应的 `origin` 远端分支 |

**日常使用建议选择 `2`，安装菜单直接回车也会选择 NPM 模式。** 源码模式需要完成本地构建，耗时取决于网络、电脑性能和依赖情况。

安装成功后会保存模式和路径，并启动 DSH、打开浏览器。如果已经发现可用的源码目录或本地 NPM 安装，启动器会直接使用它。

### 可选：添加桌面快捷方式

在启动器目录打开 PowerShell，执行：

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\tools\make-dsh-shortcut.ps1 -StartMenu
```

这会创建带图标的桌面和开始菜单快捷方式。以后双击快捷方式即可；移动启动器文件夹后，请重新生成快捷方式。

## 启动与更新

日常使用只需要双击入口，也可以在启动器目录运行：

```powershell
.\dsh-quicklauncher.cmd
```

每次启动大致经过以下步骤：

```text
双击启动器
  ├─ 本地端口已可连接 → 直接打开浏览器
  └─ 本地端口未开放
       → 查找安装，必要时引导安装
       → 检查更新，按选择更新或跳过
       → 在独立窗口启动 DSH
       → 等待端口可用，打开浏览器
```

默认地址为 `http://127.0.0.1:3080/`，启动等待时间最长约 120 秒。DSH 在独立窗口中运行，**关闭那个服务窗口即可停止服务**；关闭浏览器页面不会停止服务。

### 发现更新时

- **输入 `1` 或直接回车**：立即更新，然后尝试启动。
- **输入 `2`**：跳过本次更新，启动已安装版本。

跳过记录保存在 `.dsh-launch-skip.txt`。检测到的更新信息没有变化时，不会重复询问；删除这个文件可恢复提示。

| 模式 | 更新行为 |
| --- | --- |
| NPM 模式 | 在对应安装目录执行 `npm install @deepseek-ai/dsh@latest` |
| 源码模式 | 检查远端后，以 `git merge --ff-only` 合并当前分支的远端更新，执行 `pnpm install`；代码发生变化时再运行 `pnpm run build` |

源码更新检测到未提交改动时会跳过自动更新；本地与远端分支无法快进合并时，更新会中止。检查更新本身会联网，源码模式还会执行 `git fetch` 更新 Git 元数据。

更新检查失败后，启动器仍会尝试启动现有安装。**更新失败不提供自动回滚**，尤其是源码已经合并、依赖安装或构建随后失败的情况，需要查看窗口中的错误信息。

## 常见问题

### 已经安装过 DSH，还需要再装吗？

启动器会读取保存的配置，并尝试发现已有的源码目录或本地 NPM 安装。源码查找范围包括启动器所在目录及附近的祖先目录、其中的 `deepseek-harness` 子目录，以及 `%USERPROFILE%\deepseek-harness` 等位置。

NPM 模式默认使用本项目的 `tools\dsh-npm` 目录。通过 `npm install -g` 安装的全局 DSH 不会被直接识别为这个本地安装。

### 为什么再次双击没有检查更新？

如果目标端口已经可以连接，启动器会直接打开浏览器，并跳过安装与更新流程。要检查更新，先关闭正在运行 DSH 的服务窗口，再启动一次。

### 浏览器打开了，但页面不是 DSH，或者没有正常显示？

当前启动器通过本地 TCP 端口判断服务是否可用，不会进一步验证响应是否来自 DSH。请查看服务窗口的输出，并确认端口没有被其他程序占用。需要换端口时，在启动器目录运行：

```powershell
$env:DSH_WEB_PORT = '3081'
.\dsh-quicklauncher.cmd
```

启动器目前打开的是普通本地首页，不会自动拼接认证 token；如果 DSH 提示认证，请按其界面或服务日志中的说明操作。

### 如何清除保存的运行方式？

```powershell
.\dsh-quicklauncher.cmd --reset
```

这只删除保存的模式和路径配置，保留已安装的 DSH、用户数据和跳过更新的记录。下次运行仍会自动查找已有安装，因此不一定重新显示安装菜单。

已有两种可用安装时，可以通过 `DSH_LAUNCHER_MODE` 优先选择其中一种，见下方配置表。

### 源码安装失败怎么办？

查看安装窗口最后显示的错误。源码安装流程失败后，启动器会询问是否改用 NPM 模式，可以选择它继续完成安装。

## 进阶配置

以下变量在启动器运行前设置。例如，临时跳过更新检查：

```powershell
$env:DSH_LAUNCHER_SKIP_CHECK = '1'
.\dsh-quicklauncher.cmd
```

这种写法只影响当前 PowerShell 会话及其启动的进程。从资源管理器双击时如需使用相同设置，请配置 Windows 用户环境变量。

| 环境变量 | 作用与默认值 |
| --- | --- |
| `DSH_LAUNCHER_SKIP_CHECK=1` | 跳过更新检查；缺少安装时仍会进入安装流程 |
| `DSH_LAUNCHER_MODE=source` 或 `npm` | 优先选择运行模式，覆盖保存的模式；目标安装须可用，否则会继续查找或引导安装 |
| `DSH_LAUNCHER_REPO` | 指定源码安装或查找路径；默认安装到 `%USERPROFILE%\deepseek-harness` |
| `DSH_LAUNCHER_TOOLS` | 指定 NPM 安装目录；默认为启动器目录下的 `tools\dsh-npm` |
| `DSH_LAUNCHER_CONFIG` | 指定配置文件；默认为启动器目录下的 `.dsh-launch-config.json` |
| `DSH_LAUNCHER_NO_AUTODISCOVER=1` | 关闭额外的源码目录自动搜索，仍会检查显式指定和保存的源码路径 |
| `DSH_WEB_PORT` | Web 服务端口，默认为 `3080` |
| `DSH_HOME` | 传给 DSH 的用户目录，默认为 `%USERPROFILE%\.dsh` |

保存的有效安装路径会优先使用。需要更换目录时，可先用 `--reset` 清除配置，再设置路径变量后运行。

## 文件与维护

<details>
<summary>展开查看目录、辅助工具与诊断参数</summary>

### 主要文件

```text
dsh-quicklauncher/
├── dsh-quicklauncher.cmd       # 双击入口
├── dsh-quicklauncher.ps1       # 安装、检查更新与启动逻辑
├── assets/                    # 图标及预览图
├── tools/
│   ├── make-dsh-shortcut.ps1   # 创建快捷方式
│   ├── make-dsh-icon.mjs       # 生成图标素材
│   └── fix-dsh-icon.ps1        # 修复快捷方式图标显示
├── package.json               # 项目元数据与辅助命令
├── LICENSE
└── README.md
```

运行过程中可能生成：

| 路径 | 用途 |
| --- | --- |
| `.dsh-launch-config.json` | 保存运行模式、安装路径 |
| `.dsh-launch-skip.txt` | 保存跳过更新的记录 |
| `tools/dsh-npm/` | 默认的 NPM 模式安装目录 |

以上路径已在 `.gitignore` 中忽略。DSH 用户目录由 `DSH_HOME` 决定，与启动器配置分开存放。

### 图标工具

```powershell
# 重新生成图标；需要可加载的 sharp 模块
node .\tools\make-dsh-icon.mjs

# 生成图标并输出终端预览
node .\tools\make-dsh-icon.mjs --preview

# 修复快捷方式的图标显示
powershell -NoProfile -ExecutionPolicy Bypass -File .\tools\fix-dsh-icon.ps1
```

图标配色、粒子与连线在 `tools/make-dsh-icon.mjs` 中调整；生成器会覆盖输出的 SVG、PNG 和 ICO。可以用 `SHARP_PATH` 指定已安装的 `sharp` 模块路径。

### 常用诊断参数

```powershell
.\dsh-quicklauncher.cmd --smoke-version
.\dsh-quicklauncher.cmd --smoke-launch
```

| 参数 | 行为 |
| --- | --- |
| `--smoke-version` | 有可用安装时输出模式、版本、工具链、端口与更新检测结果；缺少安装时输出路径检测信息 |
| `--smoke-launch` | 有可用安装时打印解析出的启动命令，不启动服务 |
| `--smoke-run` | 执行真实流程，但不打开浏览器、不等待结束时的按键；仍可能安装、更新、写配置并启动服务，也可能需要菜单输入 |

诊断参数不能一概视为“无副作用”：`--smoke-version` 会进行联网检查，源码模式可能执行 `git fetch`；源码模式的工具链检查也可能尝试安装缺失的 pnpm。

维护脚本时，请保留 `dsh-quicklauncher.ps1` 的 **UTF-8 BOM** 和 `.cmd` 文件的 **CRLF 换行**，以兼容 Windows PowerShell 5.1 与命令提示符。

</details>

## 贡献与许可

欢迎提交 [Issue](https://github.com/S1GHLE/dsh-quicklauncher/issues) 或 Pull Request。反馈问题时，请附上运行模式、Node.js 版本和相关错误输出，并移除密钥、token 等敏感信息。

本项目以文件夹形式分发，未发布到 npm；它与 `dsh-quickstart` 是各自独立的社区项目。

图标中的鲸鱼图形取自 DeepSeek Harness 仓库的 `apps/web/public/favicon.svg`，相关品牌与标志权利归原权利人所有。

代码采用 [MIT License](LICENSE)。
