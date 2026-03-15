# Progress

## In Progress

- M2: Git 变更管理（主体完成，待运行时手测）
- M3: 文件浏览器 + 侧边栏（已完成 T3.1-T3.7 主体实现，待运行时手测）
- REQ-004: 本地部署服务（主体实现完成，待运行时手测）

## Done

- [x] M1: 骨架应用 + libghostty 终端
- [x] T1.1 项目脚手架 — xcodegen + SwiftUI 三栏布局 + entitlements
- [x] T1.2 Ghostty 集成 — submodule + setup.sh (zig build + SHA 缓存) + xcframework 链接
- [x] T1.3 终端视图 — GhosttyApp/Config/Input/Terminal + TerminalPanel (NSViewRepresentable)
- [x] T1.4 终端功能增强 — shell fallback、recursive config、配置快照与 diagnostics
- [x] T1.5 多标签 + 分屏 — 应用内 tabs、多级分屏、Cmd+T/W/1-9/D/Shift+D/Arrow
- [x] T1.P1 终端标题追踪 — 监听 `SetTitle/SetTabTitle` action 并更新 Tab 标题
- [x] M2-T2.1 GitService — porcelain 解析 + add/unstage/commit/diff/checkout
- [x] M2-T2.2 Changes Panel — 分组列表 + 单文件/批量 stage 操作 + commit 输入区
- [x] M2-T2.3 Diff View — unified diff + 加减行着色 + 轻量语法高亮
- [x] M2-T2.4 FileWatcher — 目录监听 + 300ms 防抖自动刷新
- [x] M2-T2.5 Branch/Remote — ahead/behind + create/delete + fetch/pull/push
- [x] M2-T2.6 Discard Changes — 单文件/批量丢弃 + 确认弹窗（modified/untracked）
- [x] M3-T3.1 文件树 — 递归树、目录优先排序、图标映射、git ignored 过滤
- [x] M3-T3.2 Git 状态着色 — 文件颜色标注 + 父目录递归传播
- [x] M3-T3.3 文件交互 — 右键菜单、变更文件跳转 Diff、普通文件只读预览
- [x] M3-T3.4 项目管理 — 项目列表持久化、打开/切换项目、上下文联动 Git/File 面板
- [x] M3-T3.5 预览与搜索增强 — Cmd+P 快速查找 + 轻量语法高亮
- [x] M3-T3.6 文件拖拽 — 文件树拖拽到 Terminal 粘贴路径
- [x] M3-T3.7 状态优化 — A/M/D/R/U 细粒度状态 + ignored 前缀压缩
- [x] 编译验证通过 (`xcodebuild -scheme openOwl -configuration Debug build`)
- [x] REQ-004-T1 DeploymentProcessManager — Process 生命周期、SIGTERM→SIGKILL、日志流式写入
- [x] REQ-004-T2 DeploymentStore — 创建/启动/停止/重启/删除、UserDefaults 持久化、分支轮询、PID 恢复
- [x] REQ-004-T3 ViewTab + ContentView 集成 — `.deployments` tab + DeploymentPanelView
- [x] REQ-004-T4 DeploymentPanelView — 左侧列表 + 右侧详情（状态/按钮/配置/实时日志）
- [x] REQ-004-T5 DeploymentRow + SidebarView — Sidebar 状态行 + 右键菜单 + 点击跳转 Deploy tab
- [x] REQ-004-T6 CreateDeploymentSheet — 创建部署表单 + 自动获取 remote URL + Deploy 按钮
- [x] REQ-004-T7 MenuBarExtra 系统托盘 — 托盘图标 + 部署状态菜单 + Start/Stop 操作
- [x] REQ-004-T8 AppDelegate — 有运行中部署时关闭窗口不退出 app

## Pending Issues

- M2 运行时手测待完成（Xcode Cmd+R）：
  - 选择仓库后的状态刷新
  - Stage/Unstage/Commit/Checkout 行为
  - watcher 触发自动刷新
- M2 剩余增强：
  - 运行时手测覆盖与交互细节打磨
- M3 运行时手测待完成（Xcode Cmd+R）：
  - 项目切换后 File Tree / Git Repo 同步
  - 变更文件点击跳转 Diff
  - Cmd+P 快速查找与回车打开
  - 文件拖拽到 Terminal 粘贴路径
  - 右键菜单动作（Reveal / Open in Terminal / Copy Path）
  - 大文件与二进制文件预览体验

## Notes

- 从 Electron 版迁移到 macOS 原生 (Swift + libghostty)
- 产品需求基本不变，技术栈完全重写
- 参考实现：Ghostty macOS app (macos/Sources/), cmux (manaflow-ai/cmux)
- GhosttyKit xcframework 按 commit SHA 缓存在 `~/.cache/openowl/ghosttykit/`
- Ghostty submodule pinned at commit `04fa71e2`
- 链接 libghostty 需要额外框架：Carbon, IOKit, UniformTypeIdentifiers
