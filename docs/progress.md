# Progress

## In Progress

- 菜单栏快捷键发现性（P0：添加 NSMenu 菜单栏）— 已调研方案，未开始实现
- M2: Git 变更管理（主体完成，待运行时手测）
- M3: 文件浏览器 + 侧边栏（已完成 T3.1-T3.7 主体实现，待运行时手测）
- REQ-004: 本地部署服务（主体实现完成，待运行时手测）
- UI review 后续：DeploymentStore 拆分（P3，分离健康检查/日志/进程管理）

## Release & Distribution

- [x] v1.0.0 发布 — OpenOwl-1.0.0.dmg (40MB) 签名 + 公证，上传到 GitHub Releases

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
- [x] App branding — 猫头鹰 icon 全尺寸 (16-1024) + 菜单栏 template icon + display name "OpenOwl"
- [x] 开源发布 — GitHub 仓库 sanvibyfish/openowl-app, GPL-3.0, README (EN + CN)
- [x] 版本更新检查器 — UpdateChecker (GitHub Releases API) + CheckForUpdatesButton + UpdateAlertView
- [x] 构建 & 发布流水线 — scripts/build-dmg.sh (xcodegen → archive → sign → DMG → notarize → staple)
- [x] 自动签名配置 — CODE_SIGN_STYLE=Automatic, DEVELOPMENT_TEAM, HARDENED_RUNTIME
- [x] 终端分屏分隔线稳定性 — SplitDividerInfo tree-path ID
- [x] Git 变更视图改进 — Animation.identity → .default, git graph 增强
- [x] .gitignore 加固 — *.cer, *.key, *.p12, *.pfx, *.dmg, build/
- [x] 编译验证通过 (`xcodebuild -scheme openOwl -configuration Debug build`)
- [x] docs/features/ 全套功能文档 — 001-006 编号文档 + README 索引
- [x] Swift Testing 基础设施 — openOwlTests target，149 个测试全部通过（14 suites）
- [x] ProjectStore 持久化迁移 — UserDefaults → `~/.openowl/openowl.json` + 一次性迁移
- [x] GitService / FileExplorerStore 可见性调整 — private → internal 支持测试访问
- [x] Cmd+P Quick Open 修复 — 终端 performKeyEquivalent 拦截问题，通过 Notification 触发
- [x] 文件切换缓存优化 — setProject() 有缓存时跳过浅扫描，避免闪烁
- [x] 文件浏览器 3 bug 修复 — lazy 展开 / Git 状态目录传播 / ESC 退出重命名
- [x] 目录树自动收缩 bug — 移除 outlineViewSelectionDidChange 的 toggle 逻辑
- [x] Git badge 布局溢出 — cell 右对齐 + nameField compression resistance = low
- [x] 文件目录面板可拖拽 — @State + DragGesture，150-500px 范围
- [x] 编辑器 tab close 按钮修复 — Image + onTapGesture 避免手势冲突
- [x] 编辑器内容溢出修复 — SourceEditor 加 .clipped()
- [x] Git Graph commit diff 完整实现 — 按文件分 section、文件列表 sidebar、图片 diff、颜色区分
- [x] MenuBar icon 处理 — 裁剪/反色/缩放到 18x18 + 36x36 template image
- [x] Sidebar 展开/收缩修复 — 文件夹行不参与 selection，点击只做展开/收缩
- [x] 项目切换性能优化 — syncActiveProjectContext 只刷新当前可见 tab 的 store
- [x] QuickOpen (Cmd+P) 修复 — firstResponder guard / ESC 关闭 / 点击外部关闭 / lazy-load
- [x] SwiftUI "publishing changes from within view updates" 修复 — DispatchQueue.main.async 延迟
- [x] 编辑器 tab 切换/关闭修复 — Button 替代 onTapGesture，去掉 ScrollView
- [x] 编辑器 SourceEditor frame 填满修复
- [x] Sidebar BranchRow 交互 — hover 复制路径 + 右键菜单
- [x] 内联重命名 Finder 风格 — plain textFieldStyle + 淡蓝背景
- [x] SidebarExpandCollapseTests (7 tests) 全部通过
- [x] 上游 PR: CodeEditTextView Typesetter CJK bug (#122)
- [x] 上游 PR: CodeEditSourceEditor MinimapView hitTest bug (#370/#371)
- [x] REQ-004-T1 DeploymentProcessManager — Process 生命周期、SIGTERM→SIGKILL、日志流式写入
- [x] REQ-004-T2 DeploymentStore — 创建/启动/停止/重启/删除、UserDefaults 持久化、分支轮询、PID 恢复
- [x] REQ-004-T3 ViewTab + ContentView 集成 — `.deployments` tab + DeploymentPanelView
- [x] REQ-004-T4 DeploymentPanelView — 左侧列表 + 右侧详情（状态/按钮/配置/实时日志）
- [x] REQ-004-T5 DeploymentRow + SidebarView — Sidebar 状态行 + 右键菜单 + 点击跳转 Deploy tab
- [x] REQ-004-T6 CreateDeploymentSheet — 创建部署表单 + 自动获取 remote URL + Deploy 按钮
- [x] REQ-004-T7 MenuBarExtra 系统托盘 — 托盘图标 + 部署状态菜单 + Start/Stop 操作
- [x] REQ-004-T8 AppDelegate — 有运行中部署时关闭窗口不退出 app
- [x] UI 审计 — 3 并行 agent 审计（架构/性能/导航），发现 2C+7H+9M+5L 问题
- [x] 性能修复 Phase 1 — ISO8601DateFormatter static 缓存、VStack→LazyVStack、Tab 状态 UserDefaults 持久化
- [x] 性能修复 Phase 2 — loadFileIfNeeded 异步化、computeGraphLayout @State+onChange 缓存
- [x] @Observable 全量迁移 — 7 个 Store 从 ObservableObject 迁移到 @Observable，去 Combine 化，16/16 测试通过
- [x] 拖入文件单引号修复 — shellEscapedPath 对齐 Ghostty 反斜杠转义，替代单引号包裹
- [x] Cmd+V 粘贴文件路径修复 — pasteFromClipboard() 优先读 fileURL（对齐 Ghostty getOpinionatedStringContents）
- [x] 导航 API 统一 — AppNavigationStore 新增 navigate(to:)/openDeployment(id:...)，8 处调用替换，Git/Files/Deploy tab 包裹 NavigationStack
- [x] FileIcons 提取 + 语义色 — Shared/FileIcons.swift 消除 3 处重复 icon 映射，AppPalette 改用系统语义色，支持亮色/暗色模式
- [x] 测试补充 — FileIconsTests (15)、AppNavigationStoreTests (8)、GraphLayoutTests (8)
- [x] Liquid Glass 扩展 — EditorTabBar glassEffect + 选中 tab glassEffectWithTint、Deploy ActionButton glassEffectWithTint
- [x] Graph Layout 测试 — computeGraphLayout/GraphNode/GraphLayout 从 private 提升为 internal 以支持测试
- [x] Sidebar bellCount 缓存 — TerminalWorkspaceStore.bellCount(for:) 轻量方法，减少 sidebar 观察依赖
- [x] Terminal Search (Cmd+F) — TerminalSearchState (@Observable) + TerminalSearchOverlay (SwiftUI 浮层) + per-pane 独立搜索状态 + GhosttyApp 搜索回调 + debounce 策略 (>=3字符立即, <3字符 300ms)

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
