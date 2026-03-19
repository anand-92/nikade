# 终端通知功能：重复造轮子的教训

> 日期：2026-03-19 | 影响：浪费多轮迭代实现已有现成方案的功能 | 最终方案：3 行 ghostty 配置

---

## 1. 问题

用户希望终端中 Claude Code 完成任务时收到通知。当时 openOwl 仅在侧边栏 badge 追踪 bell 状态，无系统通知。

## 2. 时间线

| 轮次 | 方案 | 结果 | 失败原因 |
|------|------|------|---------|
| 1 | Bell 事件触发系统通知 | 部分成功 | Claude Code 根本不发 bell 字符，方案前提不成立 |
| 2 | 终端标题变化检测 | 失败 | 太简陋——检测标题是否包含 "@" 来判断回到 shell 提示符，对 Claude Code TUI 无效 |
| 3 | 滚动条静默检测 | 被否决 | 用户指出 CPU 开销问题，方案本身也不可靠 |
| 4 | **ghostty 原生 `notify-on-command-finish`** | **成功** | 3 行配置解决 |

### 轮次 1：Bell 通知

- 添加了 `NSSound.beep()`、Dock 弹跳、`UNUserNotificationCenter`
- 发现问题：app 在后台时 bell 事件不触发——`DispatchQueue.main.async` 被 macOS 节流
- 修复：`handleAction` 回调从 `DispatchQueue.main.async` 改为同步调用（tick() 已在主线程）
- 但 Claude Code 不发 bell 字符，整个方案方向错误

### 轮次 2：标题变化检测

- 监听终端标题变化，判断从命令名回到 shell 提示符（包含 "@"）
- 用户立即指出："如果他是在 claude code 里面呢？"——Claude Code 是 TUI，不会退出到 shell

### 轮次 3：滚动条静默检测

- 追踪终端输出频率，输出停止 5 秒后发通知
- 实现了 per-pane Task 计时器，又重构为单 Timer + 时间戳追踪
- 用户评价："你这样不会吃 cpu 吗？" + "这个方案不好，上网查一下别人咋做的"

### 轮次 4：搜索现有方案

- 搜索发现 ghostty 内建 `notify-on-command-finish` 功能
- 基于 OSC 133 shell integration，ghostty 自己检测命令执行完成
- 3 行配置：
  ```
  notify-on-command-finish = unfocused
  notify-on-command-finish-action = bell
  notify-on-command-finish-after = 5
  ```
- ghostty 命令完成后发 RING_BELL → 已有的 bell handler 播放通知音
- **删除了所有自建的检测代码**

## 3. 过程中发现的子问题

| 问题 | 原因 | 修复 |
|------|------|------|
| `NSSound.beep()` 静音 | 系统提醒音量为 0 时无声 | 改用 `NSSound(contentsOfFile:)` 加载 .aiff 文件 |
| 后台 app 收不到 bell 事件 | `DispatchQueue.main.async` 被 macOS 节流 | 改为同步调用（tick() 已在主线程） |
| 后台 ghostty 事件循环停止 | 无 tick 驱动 | 添加后台 tick timer |
| Debug 构建无通知权限 | macOS 通知权限按 bundle ID 管理 | 用户手动在系统设置中开启 |
| 通知声音不可配置 | 硬编码 | 添加 Settings UI，支持 14 种系统音效 + None |

## 4. 根因

**没有先搜索现有方案就开始造轮子。**

ghostty 拥有 200+ 配置项，`notify-on-command-finish` 通过 OSC 133 shell integration 完美解决了命令完成检测。我们花了约 8 轮迭代构建自定义检测（bell、标题匹配、滚动条轮询），直到用户说"上网查一下"才找到正确方案。

## 5. 解决方案

最终方案极其简单：在 ghostty 配置中添加 3 行，加上已有的 bell handler 播放通知音。所有自建的检测代码全部删除。

## 6. 教训

### 核心教训：先搜索，后动手

在实现任何功能前，**必须先搜索框架/库是否已有现成方案**。尤其是：
- 终端相关功能 → 先查 ghostty 配置文档（200+ 选项）
- 系统集成功能 → 先查 macOS API 和系统能力
- 通用需求 → 先搜索社区方案

### 其他教训

1. **`DispatchQueue.main.async` 对后台 macOS app 不可靠**——macOS 会节流后台 app 的 GCD 调度。已在主线程时应直接同步调用。
2. **`NSSound.beep()` 依赖系统提醒音量**——音量为 0 时完全静音。可靠的音频播放应使用 `NSSound(contentsOfFile:)`。
3. **用户说"上网查一下"时立即停下来搜索**——不要继续在错误方向上迭代。
4. **自建方案的复杂度是一个危险信号**——如果实现一个常见功能需要复杂的自定义逻辑（轮询、计时器、启发式检测），很可能已有更优雅的现成方案。
