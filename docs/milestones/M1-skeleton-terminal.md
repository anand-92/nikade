# M1: 骨架应用 + libghostty 终端

## 目标

搭建 macOS 原生应用骨架，集成 libghostty 实现可用的终端。这是最关键的里程碑。

## 任务

### T1.1 项目脚手架
- [ ] 创建 Xcode 项目 (macOS App, SwiftUI lifecycle)
- [ ] 配置 minimum deployment target (macOS 14.0+)
- [ ] 基础 SwiftUI 窗口 + 三栏布局 (Sidebar / Content / Inspector)

### T1.2 Ghostty 集成
- [ ] 添加 Ghostty 作为 git submodule
- [ ] 配置 Zig 构建脚本编译 libghostty 静态库
- [ ] 创建 bridging header 导入 ghostty.h
- [ ] 验证 Swift 可以调用 ghostty C API

### T1.3 终端视图
- [ ] 实现 GhosttyApp.swift — ghostty_app_t 生命周期管理
- [ ] 实现 GhosttyTerminal.swift — ghostty_surface_t 封装
- [ ] 实现 TerminalView (NSView + CAMetalLayer)
- [ ] 通过 NSViewRepresentable 桥接到 SwiftUI
- [ ] 键盘输入 → ghostty_surface_key()
- [ ] 窗口 resize → ghostty_surface_set_size()

### T1.4 终端功能
- [ ] Shell 自动检测和启动
- [ ] 读取 ~/.config/ghostty/config
- [ ] 基础主题/字体配置
- [ ] 滚动回看 (scrollback)

### T1.5 多标签 + 分屏
- [ ] Tab bar (Cmd+T/W/1-9)
- [ ] 分屏 (Cmd+D, Cmd+Shift+D)
- [ ] 焦点切换 (Cmd+Arrow)

## 完成标准

- 能打开应用，看到一个可交互的终端
- 终端文字渲染质量与原生 Ghostty 一致
- 能运行 `ls`、`vim`、`htop` 等常见工具
- 能创建多标签和分屏

## 参考

- Ghostty macOS: `macos/Sources/`
- cmux: `github.com/manaflow-ai/cmux`
