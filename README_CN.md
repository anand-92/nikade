<p align="center">
  <img src="openOwl/Assets.xcassets/AppIcon.appiconset/icon_256x256.png" width="128" height="128" alt="OpenOwl">
</p>

<h1 align="center">OpenOwl</h1>

<p align="center">
  <strong>macOS 原生 Git GUI + 终端桌面应用</strong><br>
  基于 Swift、<a href="https://github.com/ghostty-org/ghostty">libghostty</a> 和 Metal GPU 渲染构建
</p>

<p align="center">
  <a href="#功能">功能</a> &bull;
  <a href="#安装">安装</a> &bull;
  <a href="#构建">构建</a> &bull;
  <a href="#架构">架构</a> &bull;
  <a href="README.md">English</a>
</p>

---

## 什么是 OpenOwl？

OpenOwl 是一款 macOS 原生桌面应用，将 **GPU 加速终端**、**Git GUI** 和**文件编辑器**集成在一个窗口中。不内建 AI — 终端完全开放，你可以自由使用任何 CLI 工具。

## 功能

- **终端** — 基于 [libghostty](https://github.com/ghostty-org/ghostty)，Metal GPU 渲染。支持标签页、分屏、拖拽重排。
- **Git 变更** — 暂存、取消暂存、丢弃文件。并排 diff 视图。提交消息。分支追踪。
- **文件浏览器** — NSOutlineView 文件树，带 git 状态标记。多标签代码编辑器，tree-sitter 语法高亮。快速打开（Cmd+P）模糊搜索。
- **项目侧边栏** — 多项目支持。Git worktree 管理（创建、归档、重命名）。每个项目独立的终端隔离。
- **本地部署** — 克隆、构建、启动本地服务。健康检查监控。系统托盘状态显示。

## 截图

> 即将添加

## 安装

### 系统要求

- macOS 14.0 (Sonoma) 或更高版本
- Apple Silicon 或 Intel Mac

### 下载

> 预编译版本即将推出。目前请从源码构建。

## 构建

### 前置条件

- Xcode 15.0+
- [XcodeGen](https://github.com/yonaskolb/XcodeGen)（`brew install xcodegen`）
- [libghostty](https://github.com/ghostty-org/ghostty) — 参考[集成指南](docs/features/001-libghostty-integration.md)

### 步骤

```bash
# 克隆仓库
git clone https://github.com/sanvibyfish/openowl-app.git
cd openowl-app

# 生成 Xcode 项目
xcodegen generate

# 在 Xcode 中打开并运行
open openOwl.xcodeproj
# Cmd+R 构建运行
```

### 命令行构建

```bash
xcodebuild -scheme openOwl -configuration Debug build
```

## 架构

```
openOwl/
├── App/                    # SwiftUI App 入口
├── Features/
│   ├── Terminal/           # libghostty 终端（标签、分屏、拖拽）
│   ├── Git/                # Git 变更面板、Diff 视图
│   ├── FileExplorer/       # 文件树、多标签编辑器、快速打开
│   ├── Deployment/         # 本地部署服务
│   └── Sidebar/            # 项目列表、worktree 管理
├── Services/
│   ├── GitService.swift    # git CLI 封装
│   └── FileWatcher.swift   # 文件系统监听
├── Ghostty/                # libghostty Swift 封装
│   ├── GhosttyApp.swift    # ghostty_app_t 生命周期
│   ├── GhosttyTerminal.swift # ghostty_surface_t + Metal 渲染
│   └── GhosttyConfig.swift # 配置管理
└── Shared/                 # 主题、常量、工具
```

### 技术栈

| 组件 | 技术 |
|------|------|
| 语言 | Swift |
| UI | SwiftUI + AppKit（混合） |
| 终端 | libghostty（Zig 编译，Metal GPU 渲染） |
| 编辑器 | [CodeEditSourceEditor](https://github.com/CodeEditApp/CodeEditSourceEditor)（tree-sitter） |
| Git | 基于 Process 的 git CLI 调用 |
| 文件系统 | FileManager + DispatchSource |
| 构建 | Xcode + SPM + XcodeGen |

## 贡献

欢迎贡献！请先阅读现有代码并遵循项目规范。

1. Fork 本仓库
2. 创建功能分支（`git checkout -b feature/amazing-feature`）
3. 提交更改
4. 推送到分支（`git push origin feature/amazing-feature`）
5. 创建 Pull Request

## 许可证

本项目使用 GNU 通用公共许可证 v3.0 — 详见 [LICENSE](LICENSE) 文件。

## 致谢

- [Ghostty](https://github.com/ghostty-org/ghostty) — 终端模拟器库
- [CodeEditApp](https://github.com/CodeEditApp) — 源代码编辑器组件
- [cmux](https://github.com/manaflow-ai/cmux) — libghostty 集成参考
