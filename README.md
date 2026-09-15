# dsh-keepup

**DeepSeek Harness 的一键启动器：双击检查更新 → 按需更新 → 启动 Web UI。**

Windows 上双击一个图标就能用 DSH，而且不会让你停留在旧版本上。

> 本项目是社区作品，与 DeepSeek 官方无隶属关系，也未获官方背书。详见[免责声明](#免责声明)。

---

## 它解决什么问题

`dsh web` 本身没问题，问题在于**你会忘记更新它**。DSH 迭代很快（每周多个版本），等你哪天发现自己落后了几十个提交、或者构建产物早就过期时，通常已经踩到过时的 bug 了。

`dsh-keepup` 在每次启动前插一步：

1. 探测 `127.0.0.1:3080`——DSH 已经在跑就直接开浏览器，不重复拉起第二个实例；
2. 检查是否有更新，**有的话弹菜单让你选**"立即更新"还是"暂不更新"；
3. 按你的选择更新（或跳过），然后启动服务、等服务就绪、用默认浏览器打开带 token 的地址。

选"暂不更新"会被记住，直到出现**新的**更新才会再问。

### 和现成方案的区别

DSH 启动器已经有人在做，主要是 [`dsh-quickstart`](https://www.npmjs.com/package/dsh-quickstart)。我们的侧重点不同：

| | dsh-quickstart | **dsh-keepup** |
| --- | --- | --- |
| 双击启动 | ✅ | ✅ |
| 就绪轮询 + 自动开浏览器 | ✅ | ✅ |
| 隐藏控制台窗口 | ✅ | ❌ 保留窗口（能看到更新进度和日志） |
| 看门狗自动重启 | ✅ | ❌ |
| **检查更新并提示** | ❌ | ✅ |
| **一键完成更新**（拉代码 / 重装包 + 重建） | ❌ | ✅ |
| **自动识别源码环境，缺失时引导安装** | ❌ | ✅ |
| 前置要求 | 需先 `npm i -g @deepseek-ai/dsh` | 只要 Node.js，其余它自己装 |
| 分发形态 | npm 全局包 | 一个文件夹，拷走即用 |

如果你只想"双击打开、别管更新"，`dsh-quickstart` 可能更合你意。如果你想"永远是最新的、而且不想手动折腾构建"，这款可能更合你意。

---

## 前置要求

| 场景 | 需要什么 |
| --- | --- |
| 启动已装好的 DSH | **Node.js `^22.19.0` 或 `>=24.0.0`**（注意：Node 23 不被 DSH 接受） |
| 选「源码模式」 | 额外需要 git、pnpm（pnpm 缺失时会自动尝试安装） |

Windows PowerShell 5.1 即可，不需要 PowerShell 7。

---

## 快速开始

1. 把这个文件夹放到任意位置（**别放进 DSH 源码目录里面**）；
2. 双击 `dsh-keepup.cmd`；
3. 首次运行会让你选运行方式：

   ```
   1) 源码模式（推荐开发者）
      git clone + pnpm install + pnpm run build
      需要 git 和 pnpm；约 1.5 GB，首次构建十几分钟
      更新方式：git pull，能看到每个提交

   2) NPM 模式（推荐只想用的人）
      npm install @deepseek-ai/dsh
      只需要 Node.js；约 214 MB，一分钟装完
      更新方式：跟随 npm 发布版

   3) 退出
   ```

   选择会写进 `.dsh-launch-config.json`，以后不再询问。

4. 想要桌面图标：

   ```powershell
   powershell -ExecutionPolicy Bypass -File tools\make-dsh-shortcut.ps1 -StartMenu
   ```

   然后右键桌面图标 → **固定到任务栏**，就能一键启动了。

### 两种模式怎么选

| | 源码模式 | NPM 模式 |
| --- | --- | --- |
| 磁盘占用 | 约 1.5 GB | 约 214 MB |
| 首次耗时 | 十几分钟（含构建） | 约 1 分钟 |
| 前置依赖 | Node + git + pnpm | 只要 Node |
| 能看到每个提交 | ✅ | ❌ 只有版本号 |
| 更新方式 | `git pull` + 重新构建 | `npm install @latest` |
| 首次构建失败的风险 | 有（原生扩展需要 C++ 工具链） | 基本没有 |

**只想用 DSH → 选 NPM 模式。想跟着源码走、甚至改代码 → 选源码模式。**

源码模式首次构建失败时，它会问你要不要改用 NPM 模式先把 DSH 跑起来。

---

## 日常使用

```powershell
# 双击即可，等价于：
.\dsh-keepup.cmd

# 或者直接调 PowerShell
powershell -ExecutionPolicy Bypass -File dsh-keepup.ps1
```

### 参数与开关

| 开关 | 作用 |
| --- | --- |
| `--reset` | 删除保存的模式选择，下次重新询问 |
| `--smoke-run` | 走真实流程，但不打开浏览器、不等按键（用于自动化测试） |
| `--smoke-version` | 只打印检测结果（版本、模式、工具链、端口），不启动 |
| `--smoke-launch` | 只打印解析出的启动命令 |
| `--smoke-menu` | 用示例数据渲染更新提示 |
| `--smoke-install` | 用示例数据渲染安装菜单 |

`--smoke-*` 系列都不产生副作用：不会安装任何东西，也不会写配置文件。

### 环境变量

| 变量 | 作用 |
| --- | --- |
| `DSH_LAUNCHER_SKIP_CHECK=1` | 跳过更新检查，直接启动 |
| `DSH_LAUNCHER_MODE=source\|npm` | 强制指定运行模式，覆盖配置文件 |
| `DSH_LAUNCHER_REPO=<路径>` | 指定源码 checkout 位置 |
| `DSH_LAUNCHER_TOOLS=<路径>` | 指定 NPM 模式的安装目录（默认 `tools\dsh-npm`） |
| `DSH_LAUNCHER_CONFIG=<路径>` | 换一个配置文件路径（默认项目根下的 `.dsh-launch-config.json`） |
| `DSH_LAUNCHER_NO_AUTODISCOVER=1` | 不做源码目录自动探测 |
| `DSH_WEB_PORT=<端口>` | 换端口（默认 3080） |
| `DSH_HOME=<路径>` | DSH 的用户目录（默认 `%USERPROFILE%\.dsh`） |

### 强制重新探测源码目录

默认情况下它会按这个顺序找源码 checkout，找到就用源码模式：

1. `DSH_LAUNCHER_REPO` 指定的路径
2. 配置文件里记的路径
3. 启动器所在目录、以及它的祖先目录下的 `deepseek-harness\`
4. `%USERPROFILE%\deepseek-harness`

想让它在没有配置的情况下不要自动乱认，设 `DSH_LAUNCHER_NO_AUTODISCOVER=1`。

---

## 目录结构

```
dsh-keepup/
├── dsh-keepup.cmd          # 双击入口（唯一需要点的文件）
├── dsh-keepup.ps1          # 启动器逻辑，必须和 .cmd 同级
├── assets/                 # 全部图标素材
│   ├── dsh-icon.ico        # 多尺寸 Windows 图标（16/24/32/48/64/128/256）
│   ├── dsh-icon.svg        # 矢量源图，改图标从这里改
│   ├── dsh-icon.png        # 512px PNG
│   └── dsh-icon-<size>.png # 各尺寸 PNG 预览
├── tools/                  # 生成与修复脚本，平时用不到
│   ├── make-dsh-icon.mjs       # 从 SVG 生成 .ico 和全套 PNG
│   ├── make-dsh-shortcut.ps1   # 创建桌面/开始菜单快捷方式
│   └── fix-dsh-icon.ps1        # 修 Windows 图标缓存导致的旧图标
├── .gitignore
├── LICENSE
├── package.json            # 仅用于元数据和脚本别名，不适合 npm 安装
└── README.md
```

运行后会额外生成（已在 `.gitignore` 中忽略）：

| 路径 | 说明 |
| --- | --- |
| `.dsh-launch-config.json` | 记住你选的模式和路径 |
| `.dsh-launch-skip.txt` | 记住"暂不更新"的选择 |
| `tools/dsh-npm/` | NPM 模式安装的依赖（约 214 MB） |

---

## tools/ 里的脚本

```powershell
# 重新生成图标（需要 node 和 sharp）
node tools\make-dsh-icon.mjs
node tools\make-dsh-icon.mjs --preview      # 顺便在终端打印 ASCII 构图预览

# 重建快捷方式（桌面 + 开始菜单）
powershell -ExecutionPolicy Bypass -File tools\make-dsh-shortcut.ps1 -StartMenu

# 换过图标后桌面还显示旧的：刷新 Windows 图标缓存
powershell -ExecutionPolicy Bypass -File tools\fix-dsh-icon.ps1 -RestartExplorer
```

`make-dsh-icon.mjs` 需要 `sharp`。它会先试 `SHARP_PATH` 环境变量指定的路径，再试正常模块解析；如果本地装了 DSH，它的 profile 里通常就带着 sharp。

---

## 关于图标

图标里的鲸鱼标志来自 DSH 开源仓库自带的 favicon（`apps/web/public/favicon.svg`），底色、网格和粒子是后加的。

改配色和粒子直接编辑 `tools/make-dsh-icon.mjs` 顶部的 `C`（调色板）、`PARTICLES`（光点坐标）、`LINKS`（连线），然后重跑 `node tools/make-dsh-icon.mjs`，`assets/dsh-icon.svg` 会同步重新生成。

---

## 安全性说明

**这个启动器会真的执行更新**，不是只提示。具体来说：

- **源码模式**：会在你的 checkout 里跑 `git fetch` / `git merge --ff-only` / `pnpm install` / `pnpm run build`。它**不会**碰你的分支历史（只用快进合并），工作区有未提交改动时会拒绝自动更新。
- **NPM 模式**：会跑 `npm install @deepseek-ai/dsh@latest`。
- 两条路都**只在你从菜单里选"立即更新"之后**才执行。你不选，它就只启动。
- 想完全禁掉更新检查：设 `DSH_LAUNCHER_SKIP_CHECK=1`。

`git fetch` 只写入 `FETCH_HEAD`，不动工作区和本地分支。

---

## 免责声明

- 本项目是**社区作品**，由第三方维护，与 DeepSeek 官方**没有隶属、合作或授权关系**，也不代表官方背书。
- **"DeepSeek Harness"** 是深度求索公司的注册商标。本项目遵循 [DeepSeek Harness 品牌素材使用规范](https://github.com/deepseek-ai/deepseek-harness/blob/master/BRAND_GUIDELINES.zh.md)：项目名使用社区推荐的 **DSH** 缩写，描述性文字中用 "DeepSeek Harness" 说明真实关系。
- 图标中的鲸鱼标志版权归 DeepSeek 所有，取自其开源仓库，仅用于标识本工具的服务对象。
- 使用本工具产生的任何后果（包括更新失败、构建失败、数据丢失）由使用者自行承担。

---

## 贡献

欢迎提 Issue 和 PR。

---

## 许可

[MIT](LICENSE)
