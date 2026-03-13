# Progress

## In Progress

- M1: 骨架应用 + libghostty 终端

## Done

- [x] T1.1 项目脚手架 — xcodegen + SwiftUI 三栏布局 + entitlements
- [x] T1.2 Ghostty 集成 — submodule + setup.sh (zig build + SHA 缓存) + xcframework 链接
- [x] T1.3 终端视图 — GhosttyApp/Config/Input/Terminal + TerminalPanel (NSViewRepresentable)
- [x] 编译验证通过 (xcodebuild Debug build succeeded)

## Pending Issues

- 运行时验证待完成：需要在 Xcode 中 Cmd+R 运行，确认终端可交互
- T1.4 终端功能增强（主题/字体配置、scrollback）
- T1.5 多标签 + 分屏

## Notes

- 从 Electron 版迁移到 macOS 原生 (Swift + libghostty)
- 产品需求基本不变，技术栈完全重写
- 参考实现：Ghostty macOS app (macos/Sources/), cmux (manaflow-ai/cmux)
- GhosttyKit xcframework 按 commit SHA 缓存在 ~/.cache/openowl/ghosttykit/
- Ghostty submodule pinned at commit 04fa71e2
- 链接 libghostty 需要额外框架：Carbon (TIS API), IOKit, UniformTypeIdentifiers
