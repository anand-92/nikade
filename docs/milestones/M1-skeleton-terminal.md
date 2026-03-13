# M1: 骨架应用 + libghostty 终端

## 目标

搭建 macOS 原生应用骨架，集成 libghostty 实现可用终端，并补齐多标签/分屏基础交互。

## 任务

### T1.1 项目脚手架 ✅
- [x] 创建 Xcode 项目 (macOS App, SwiftUI lifecycle)
- [x] 配置 minimum deployment target (macOS 14.0+)
- [x] 基础 SwiftUI 窗口 + 三栏布局 (Sidebar / Content / Inspector)

### T1.2 Ghostty 集成 ✅
- [x] 添加 Ghostty 作为 git submodule
- [x] 配置 Zig 构建脚本编译 libghostty 静态库
- [x] 创建 bridging header 导入 ghostty.h
- [x] 验证 Swift 可以调用 ghostty C API

### T1.3 终端视图 ✅
- [x] 实现 GhosttyApp.swift — ghostty_app_t 生命周期管理
- [x] 实现 GhosttyTerminal.swift — ghostty_surface_t 封装
- [x] 实现 TerminalView (NSView + CAMetalLayer)
- [x] 通过 NSViewRepresentable 桥接到 SwiftUI
- [x] 键盘输入 → ghostty_surface_key()
- [x] 窗口 resize → ghostty_surface_set_size()

### T1.4 终端功能 ✅
- [x] Shell 自动检测和启动（优先用户配置 command；无 command 时 fallback shell）
- [x] 读取 ~/.config/ghostty/config（含 recursive includes）
- [x] 主题/字体配置透传 libghostty，并记录运行时配置快照
- [x] scrollback 由 libghostty 配置生效（读取 `scrollback-limit` 快照）

### T1.5 多标签 + 分屏 ✅
- [x] 应用内 Tab bar（Cmd+T/W/1-9）
- [x] 多级分屏（Cmd+D 左右分屏，Cmd+Shift+D 上下分屏）
- [x] 分屏焦点切换（Cmd+Arrow，边界无目标时 no-op）
- [x] `Cmd+W` 层级：分屏 > 标签 > 窗口

### P1 增强（持续迭代）
- [x] 终端标题追踪（OSC 0/2 -> Tab 标题）
- [ ] URL 检测 + Cmd+Click 打开链接
- [ ] 运行时 scrollback 调参 UI

## 本次实现说明

- 新增 `TerminalWorkspaceStore` 管理 tabs、active tab、split tree 与 focused pane。
- 新增 `TerminalSplitNode` 递归模型与 SwiftUI 递归渲染器，当前固定 50/50 比例（不含拖拽调比）。
- `ContentView` 改为「Tab 条 + ZStack 内容区」，标签切换不销毁后台终端会话。
- `GhosttyAppManager` 增加：
  - `launchProfile`（`configCommand` + `fallbackShell`）
  - pane/surface 注册与按 pane 聚焦能力
  - action 回调转发 `SetTitle/SetTabTitle`，驱动 Tab 标题更新
- `GhosttyConfig` 增加：
  - default + recursive 配置加载
  - diagnostics 聚合日志
  - `command/font-family/font-size/theme/scrollback-limit` 快照

## 验证

- [x] `xcodebuild -scheme openOwl -configuration Debug build` 通过
- [ ] Xcode 运行时手测（Cmd+R）待执行：
  - Tab/split 快捷键与 `Cmd+W` 层级
  - shell fallback 与用户 command 优先级
  - 主题/字体/scrollback 配置变更生效

## 完成标准

- 能打开应用并看到可交互终端
- 终端渲染质量与原生 Ghostty 一致
- 能运行常见 CLI 工具
- 能创建多标签和多级分屏

## 参考

- Ghostty macOS: `macos/Sources/`
- cmux: `github.com/manaflow-ai/cmux`
