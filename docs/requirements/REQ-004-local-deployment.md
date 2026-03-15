# REQ-004: 本地部署服务

## 概述

基于 openOwl 现有的 Project，用户可以创建「部署版本」—— 将项目的指定分支 clone 到隔离目录，以后台服务方式常驻运行。类似本地版 Coolify，不依赖 Docker。

## 核心场景

用户写了一个 Web 应用（或任意长驻进程），想在本地部署一份随时可用的版本，而不是每次手动开 Terminal 跑 `dev`。部署版本与开发目录完全隔离，开发过程中不影响已部署的服务。当监听分支有新 commit 时，自动拉取、重新构建并重启。

## 核心需求

### P0 — 部署版本管理

- [ ] 创建部署版本：用户在 Sidebar 的 Project 下新增部署版本
  - 配置项：名称、监听分支、构建命令（可选）、启动命令、环境变量文件路径
  - 隔离方式：`git clone` 到 `~/.openowl/deployments/<project>-<name>/`
  - 创建后自动执行首次 clone → build → start
- [ ] 环境变量：用户指定一个纯文本文件路径，格式为一行一个 `KEY=VALUE`
- [ ] 启动/停止/重启：手动控制部署版本的运行状态
- [ ] 状态展示：Sidebar 中部署版本显示运行状态（运行中 / 已停止 / 构建中 / 异常）

### P0 — 自动部署

- [ ] 分支监听：定时 `git fetch` + 比较 HEAD，检测到新 commit 后自动 pull → build → restart
- [ ] 监听间隔：内部默认合理值（如 30s），不暴露给用户

### P0 — 系统托盘

- [ ] 系统托盘图标（NSStatusItem / MenuBarExtra）
- [ ] 托盘菜单显示所有部署版本及其状态
- [ ] 托盘菜单支持 Start / Stop / Restart 操作

### P1 — 增强

- [ ] 日志查看：查看部署版本的 stdout/stderr 输出
- [ ] 删除部署版本：停止服务 + 清理 clone 目录
- [ ] 开机自启动：可选，重启 Mac 后自动恢复之前运行的部署版本
- [ ] 端口展示：配置端口后，托盘菜单可快捷打开 `http://localhost:<port>`

## 数据模型

```swift
struct Deployment: Identifiable, Codable {
    let id: String
    let projectId: String        // 关联的 Project
    var name: String             // 用户自定义名称，如 "prod"
    var watchBranch: String      // 监听的 git 分支，如 "main"
    var buildCommand: String?    // 构建命令，如 "npm run build"
    var startCommand: String     // 启动命令，如 "npm start"
    var envFilePath: String?     // 环境变量文件路径
    var port: Int?               // 可选，服务端口
    var status: DeploymentStatus
    var clonePath: String        // ~/.openowl/deployments/<project>-<name>/
    var lastDeployedCommit: String?  // 当前部署的 commit SHA
}

enum DeploymentStatus: String, Codable {
    case running
    case stopped
    case building
    case error
}
```

## 用户流程

```
1. Sidebar → Project 右边的「+」→ 「新增部署版本」
2. 弹出配置面板：
   - 名称：prod
   - 监听分支：main
   - 构建命令：npm run build
   - 启动命令：npm start
   - 环境变量文件：/path/to/.env.prod
3. 点击「部署」
4. openOwl 在后台：clone → 读取 env 文件 → build → start
5. Sidebar 中 Project 下出现「🟢 prod」
6. 系统托盘出现 openOwl 图标，菜单中可见「MyApp / prod — Running」
7. 用户继续在开发分支写代码
8. merge 到 main 后，openOwl 自动检测 → pull → rebuild → restart
```

## 技术要点

### 进程管理

- 使用 Foundation `Process` 管理子进程
- stdout/stderr 通过 `Pipe` 捕获，写入日志文件 `~/.openowl/deployments/<name>/logs/`
- 进程退出后根据 exit code 更新状态（正常停止 vs 异常退出）

### 环境变量

- 读取用户指定的纯文本文件，逐行解析 `KEY=VALUE`
- 注入到 `Process.environment` 中
- 不做模板替换、变量引用等复杂处理

### 分支监听

- 定时任务（Timer / DispatchSource）执行 `git fetch origin <branch>`
- 比较本地 HEAD 与 `origin/<branch>` 的 SHA
- 不一致时触发 `git pull` → build → restart
- 构建/部署过程中跳过本轮检测

### 系统托盘

- macOS 13+ 可用 `MenuBarExtra`（SwiftUI 原生）
- 或直接用 `NSStatusBar.system.statusItem` + `NSMenu`（AppKit，兼容性更好）
- openOwl 主窗口关闭时，如有运行中的部署版本，app 不退出而是驻留托盘

### 持久化

- 部署配置存入 UserDefaults 或 JSON 文件（与 ProjectStore 一致）
- 运行中的进程 PID 记录，app 重启后检测进程是否仍存活

## Sidebar 展示

```
├── MyApp (Project)
│   ├── main                    ← 开发分支
│   ├── feat/new-feature        ← worktree
│   └── 🟢 prod (deployed)     ← 部署版本，绿点=运行中
│
├── AnotherApp (Project)
│   ├── main
│   └── 🔴 staging (deployed)  ← 红点=异常
```

部署版本的行为与 worktree 不同：
- 点击不切换开发目录，而是展示服务状态/日志
- 右键菜单：Start / Stop / Restart / 查看日志 / 删除
