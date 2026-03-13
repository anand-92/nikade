# REQ-001: libghostty 终端集成

## 概述

使用 libghostty 实现原生 Metal GPU 渲染的终端，这是产品的核心功能。

## 核心需求

### P0 — 基础终端

- [ ] libghostty 集成：通过 C bridging header 导入，初始化 ghostty_app_t
- [ ] 终端视图：AppKit NSView + CAMetalLayer，通过 NSViewRepresentable 桥接到 SwiftUI
- [ ] PTY 管理：libghostty 内置，自动检测用户 shell (zsh/bash/fish)
- [ ] 输入处理：键盘事件转换为 ghostty_input_key_s，鼠标事件处理
- [ ] 终端配置：字体、字号、主题颜色、光标样式
- [ ] 读取 ~/.config/ghostty/config 用户已有配置

### P0 — 多标签 + 分屏

- [ ] 多标签页：Cmd+T 新建，Cmd+W 关闭，Cmd+1-9 切换
- [ ] 分屏：Cmd+D 水平分屏，Cmd+Shift+D 垂直分屏
- [ ] 焦点切换：Cmd+Arrow 在分屏间移动焦点

### P1 — 增强

- [ ] 终端标题追踪（OSC 0/2）
- [ ] 拖拽文件到终端粘贴路径
- [ ] URL 检测 + Cmd+Click 打开链接
- [ ] 滚动回看 (scrollback)

## 技术要点

### libghostty 集成方式 (参考 cmux)

1. Ghostty 作为 git submodule 引入
2. 用 Zig 编译出 libghostty 静态库
3. 通过 bridging header 导入 `ghostty.h`
4. Swift 调用 C API：
   - `ghostty_init()` → 全局初始化
   - `ghostty_config_new()` → 创建配置
   - `ghostty_app_new()` → 创建 app 实例（需提供 runtime callbacks）
   - `ghostty_surface_new()` → 创建终端 surface（自动创建 PTY）
   - `ghostty_surface_key()` → 发送键盘事件
   - `ghostty_surface_set_size()` → 调整大小

### Runtime Callbacks

Swift 需要实现以下回调供 libghostty 调用：
- `wakeup_cb` — 通知主线程有更新
- `action_cb` — 处理终端动作（标题变更、铃声等）
- `read_clipboard_cb` / `write_clipboard_cb` — 剪贴板交互
- `close_surface_cb` — 终端关闭请求

### 渲染流程

1. libghostty 维护终端状态（网格、样式、scrollback）
2. Metal 渲染由 libghostty 内部完成，直接绘制到 CAMetalLayer
3. Swift 端管理 display link timing
4. 大小变更通过 `ghostty_surface_set_size()` 传递像素尺寸和 content scale

## 参考实现

- Ghostty macOS app: `macos/Sources/Ghostty/` 和 `macos/Sources/Features/Terminal/`
- cmux: `github.com/manaflow-ai/cmux` — 第三方 libghostty 集成的最佳参考
