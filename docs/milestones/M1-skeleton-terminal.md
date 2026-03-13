# M1: 骨架应用 + libghostty 终端

## 目标

搭建 macOS 原生应用骨架，集成 libghostty 实现可用的终端。这是最关键的里程碑。

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

### T1.4 终端功能
- [ ] Shell 自动检测和启动
- [ ] 读取 ~/.config/ghostty/config
- [ ] 基础主题/字体配置
- [ ] 滚动回看 (scrollback)

### T1.5 多标签 + 分屏
- [ ] Tab bar (Cmd+T/W/1-9)
- [ ] 分屏 (Cmd+D, Cmd+Shift+D)
- [ ] 焦点切换 (Cmd+Arrow)

## 执行策略

### Phase 1: 串行（已完成）

T1.1 → T1.2 → T1.3 必须串行，因为存在强依赖：
- T1.2 依赖 T1.1 的项目结构
- T1.3 依赖 T1.2 的 xcframework 和 bridging header

### Phase 2: 运行时验证（阻塞点）

在 Xcode 中 Cmd+R 运行应用，确认：
- 终端 surface 能创建（无崩溃）
- Metal 渲染正常（非黑屏）
- 键盘输入能传递到 shell

**这一步是 T1.4 和 T1.5 的前置条件**——如果 surface 创建有问题，后续任务建立在错误基础上。

### Phase 3: Worktree 并行

T1.4 和 T1.5 相互独立，可以用 git worktree 并行开发：

```
main (验证通过的基础)
├── worktree: feature/t1.4-terminal-enhancements
│   修改文件：GhosttyConfig.swift, GhosttyApp.swift, Constants.swift
│   新增文件：无（增强现有配置逻辑）
│
└── worktree: feature/t1.5-tabs-splits
    修改文件：ContentView.swift, AppDelegate.swift
    新增文件：Features/Terminal/TabManager.swift,
              Features/Terminal/SplitView.swift
```

**并行可行性分析：**
- T1.4 主要改动在 `Ghostty/` 目录（配置加载、主题应用）
- T1.5 主要改动在 `App/` 和 `Features/` 目录（标签管理、分屏布局）
- 两者文件交集小，合并冲突风险低
- 唯一共享修改点：`ContentView.swift`（T1.5 改布局，T1.4 可能不改）

**合并顺序：** T1.4 先合并（改动更底层），T1.5 后合并（改动更上层，可能需要 rebase）

## 完成标准

- 能打开应用，看到一个可交互的终端
- 终端文字渲染质量与原生 Ghostty 一致
- 能运行 `ls`、`vim`、`htop` 等常见工具
- 能创建多标签和分屏

## 参考

- Ghostty macOS: `macos/Sources/`
- cmux: `github.com/manaflow-ai/cmux`
