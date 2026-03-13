# CLAUDE.md

## Project Overview

openOwl — macOS 原生 Git GUI + Terminal 桌面应用。基于 Swift + libghostty，Metal GPU 渲染终端。不内建 AI，开放 Terminal 让用户自由选择工具。

## Tech Stack

- Language: Swift
- UI: SwiftUI + AppKit (hybrid, terminal view 用 AppKit NSView)
- Terminal: libghostty (Zig 编译的静态库，Metal 渲染)
- Git: Process 调用 git CLI
- File system: FileManager + DispatchSource (fs events)
- Build: Xcode + SPM

## Development Rules

1. 任何代码改动如果与 `docs/` 下的文档不一致，必须同步更新对应文档
2. 产品决策变更（功能取舍、交互调整、设计修改）必须写入对应文档，不能只存在于对话中
3. 不确定的产品问题先问我，不要自行决定
4. Terminal 视图用 AppKit (NSView + CAMetalLayer)，通过 NSViewRepresentable 桥接到 SwiftUI
5. libghostty 通过 C bridging header 导入，Swift 直接调用 C API

## Common Commands

```bash
# Build (命令行)
xcodebuild -scheme openOwl -configuration Debug build

# 或直接 Xcode
open openOwl.xcodeproj
# Cmd+R 运行
```

## Architecture

```
openOwl/
├── App/                    # SwiftUI App 入口
├── Features/
│   ├── Terminal/           # libghostty 终端视图
│   ├── Git/                # Git 变更面板、Diff 视图
│   ├── FileExplorer/       # 文件浏览器
│   └── Sidebar/            # 项目列表导航
├── Services/
│   ├── GitService.swift    # git CLI 封装
│   └── FileWatcher.swift   # 文件系统监听
├── Ghostty/                # libghostty Swift 封装
│   ├── GhosttyApp.swift    # ghostty_app_t 生命周期
│   ├── GhosttyTerminal.swift # ghostty_surface_t 封装
│   └── GhosttyConfig.swift # 配置管理
└── Shared/                 # 通用工具、主题、类型
```

## Key References

- Ghostty macOS 源码: github.com/ghostty-org/ghostty/tree/main/macos
- cmux (第三方 libghostty 集成参考): github.com/manaflow-ai/cmux
- libghostty C API: ghostty repo 的 include/ghostty.h

## Documentation

- 项目总览 → docs/PROJECT.md
- 开发进度 → docs/progress.md
- 工作日志 → docs/memory/
- 复盘记录 → docs/postmortem/
- 功能文档 → docs/features/
- 需求文档 → docs/requirements/
- 里程碑 → docs/milestones/
