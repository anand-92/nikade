# libghostty 集成指南

## 概述

libghostty 是 Ghostty 终端模拟器的核心库，提供完整的终端功能：VT 解析、PTY 管理、Metal GPU 渲染。

## 集成方式 (参考 cmux 实践)

### 1. 添加 Ghostty 为 git submodule

```bash
git submodule add https://github.com/ghostty-org/ghostty.git ghostty
```

### 2. 编译 GhosttyKit xcframework

需要 Zig 编译器 (`brew install zig`)。

```bash
cd ghostty
zig build -Demit-xcframework=true -Dxcframework-target=universal -Doptimize=ReleaseFast
# 输出: macos/GhosttyKit.xcframework
```

cmux 的做法：
- `scripts/setup.sh` 自动化子模块初始化 + xcframework 构建
- 构建产物按 ghostty commit SHA 缓存到 `~/.cache/cmux/ghosttykit/`
- 项目根目录创建 symlink: `ln -sfn <cached_path> GhosttyKit.xcframework`

### 3. Xcode 配置

- Bridging Header: 只需一行 `#import "ghostty.h"`
- 链接: GhosttyKit.xcframework + 系统框架 (Metal, MetalKit, AppKit)
- 资源: 设置 `GHOSTTY_RESOURCES_DIR` 环境变量
- 设置 `TERM=xterm-ghostty` 环境变量

### 4. 初始化流程

```
ghostty_init(argc, argv)
  ↓
ghostty_config_new() → ghostty_config_load_default_files() → ghostty_config_finalize()
  ↓
ghostty_app_new(&runtime_cfg, config)    ← 需要提供 runtime callbacks
  ↓
ghostty_surface_new(app, &surface_cfg)   ← 创建终端 surface（自动启动 PTY + shell）
```

### 5. Runtime Callbacks (Swift → C function pointers)

```swift
var runtime = ghostty_runtime_config_s()
runtime.wakeup_cb = { userdata in ... }           // 通知主线程更新
runtime.action_cb = { userdata, action in ... }    // 处理终端动作
runtime.read_clipboard_cb = { userdata, ... }      // 读剪贴板
runtime.write_clipboard_cb = { userdata, ... }     // 写剪贴板
runtime.close_surface_cb = { userdata in ... }     // 关闭请求
```

### 6. 渲染

- libghostty 内部使用 Metal 渲染，直接绘制到 CAMetalLayer
- Swift 端只需提供 NSView + CAMetalLayer
- 不需要 app-level display link — 依赖 Ghostty renderer 自己的 wakeup
- `ghostty_surface_draw()` 触发渲染
- `ghostty_surface_set_size(surface, width, height)` 处理 resize

### 7. 输入

键盘事件通过 `ghostty_surface_key(surface, &event)` 传递：
- NSEvent → ghostty_input_key_s 转换
- 需要处理 key code 映射（参考 Ghostty.Input.swift）

### 8. 配置

读取 `~/.config/ghostty/config`（用户已有的 Ghostty 配置），支持：
- font-family, font-size
- theme, palette (16 色)
- background-opacity
- scrollback-limit
- cursor-style, cursor-color

## cmux 架构学习要点

### 项目结构
```
Sources/
  cmuxApp.swift                 # @main SwiftUI App 入口
  AppDelegate.swift             # AppKit delegate, 键盘路由, 分屏处理
  ContentView.swift             # 主窗口 (sidebar + workspace)
  TabManager.swift              # 中央状态管理 (ObservableObject)
  Workspace.swift               # 单个工作区 (panels + 分屏布局)
  GhosttyTerminalView.swift     # NSViewRepresentable 包装 ghostty surface
  GhosttyConfig.swift           # 读取 ghostty 配置
  Panels/
    Panel.swift                 # Panel 协议 (所有面板类型的抽象)
    TerminalPanel.swift         # 终端面板
    BrowserPanel.swift          # 浏览器面板 (WKWebView)
vendor/
  bonsplit/                     # 自定义分屏布局库
ghostty/                        # Ghostty 子模块
scripts/
  setup.sh                     # 构建自动化
```

### 关键设计模式

1. **SwiftUI + AppKit 混合架构**
   - SwiftUI 做声明式布局 (@main App, ContentView)
   - AppKit 做终端托管、键盘路由、窗口管理 (NSViewRepresentable)
   - 终端视图必须用 AppKit — 需要低级别 NSView 控制

2. **Panel 协议抽象**
   - 所有内容面板 (终端/浏览器/Markdown) 统一实现 Panel 协议
   - 属性: id, panelType, displayTitle
   - 方法: focus(), close()
   - 允许混合不同类型面板在同一分屏布局中

3. **Workspace 模型**
   - 每个 Workspace 包含 panels + bonsplit 布局 + git 状态 + 端口信息
   - TabManager (ObservableObject) 管理所有 workspace
   - ContentView 用 ZStack + visibility 保持所有 workspace 存活（类似 Electron 版的 display:none/block）

4. **Git 集成（浅层）**
   - 只显示 branch name + dirty 状态在侧边栏
   - 不执行 git 操作（commit/diff/merge 等）
   - Git 状态通过 shell 获取，存为 SidebarGitBranchState

5. **Session 持久化**
   - 退出时保存窗口/workspace/pane 布局和 cwd
   - 重启恢复布局但不恢复进程状态

6. **CLI/Socket API**
   - Unix socket 服务器，支持外部控制
   - 可通过 CLI 创建 workspace、发送按键、查询状态

## 关键文件参考

| cmux 文件 | 作用 | openOwl 对标 |
|-----------|------|-------------|
| `GhosttyTerminalView.swift` | NSViewRepresentable 终端 | Ghostty/GhosttyTerminal.swift |
| `GhosttyConfig.swift` | 读 ghostty 配置 | Ghostty/GhosttyConfig.swift |
| `TabManager.swift` | 中央状态 | 待定 (可能用 SwiftUI @Observable) |
| `Workspace.swift` | 工作区模型 | Features/Sidebar/ProjectStore |
| `ContentView.swift` | 主布局 | App/ContentView.swift |
| `Panel.swift` | 面板协议 | 可借鉴做 Terminal/Git/Files 面板 |
| `vendor/bonsplit/` | 自定义分屏 | 可直接用或参考实现 |
| `scripts/setup.sh` | 构建自动化 | scripts/setup.sh |

## 注意事项

- libghostty 的 C API 目前不是公开稳定 API，可能随 Ghostty 版本变化
- 需要 Zig 编译器来构建（不需要 Zig 开发经验，只是构建工具）
- cmux 使用 Ghostty fork (manaflow-ai/ghostty)，可能需要我们也 fork 一份
- 性能敏感路径不要加额外 allocation（cmux 特别强调 typing latency）
