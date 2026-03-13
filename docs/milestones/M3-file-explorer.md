# M3: 文件浏览器 + 侧边栏

## 目标

实现文件浏览器和项目管理侧边栏。

## 任务

### T3.1 文件树
- [x] 递归目录树 (OutlineGroup / List)
- [x] `.gitignore` 过滤（通过 `git ls-files --ignored --exclude-standard`）
- [x] 目录优先 + 字母序排序
- [x] 文件图标 (SF Symbols)

### T3.2 Git 状态着色
- [x] 文件 git status 颜色标注
- [x] 父目录颜色传播

### T3.3 文件交互
- [x] 右键菜单 (Reveal in Finder, 在终端打开, 复制路径)
- [x] 点击变更文件 → Diff 视图
- [x] 点击普通文件 → 只读预览（轻量语法高亮）

### T3.4 项目管理
- [x] 项目列表（侧边栏顶部）
- [x] 打开/切换项目 (NSOpenPanel)
- [x] 项目持久化 (UserDefaults)

### T3.5 预览与搜索增强
- [x] 文件快速查找（Cmd+P）
- [x] 文件预览语法高亮（关键词/注释/字符串）
- [x] 文件拖拽到终端（路径拖放）

### T3.6 状态与忽略优化
- [x] Git 状态细粒度映射（A/M/D/R/U）
- [x] ignored 目录前缀压缩优化

## 本次实现说明

- 新增 `ProjectStore`：
  - 维护项目列表与 active project，支持新增/切换/删除
  - 项目列表持久化到 `UserDefaults`
  - 首次启动自动注入当前工作目录
- 新增 `FileExplorerStore` + `FileExplorerView`：
  - 递归文件树构建，目录优先 + 字母序
  - 通过 Git ignored 列表过滤被忽略路径
  - 文件 git 状态着色并向父目录聚合传播（A/M/D/R/U）
  - ignored 目录前缀压缩，降低大仓库扫描匹配开销
  - 文件快速查找（Cmd+P）与搜索结果定位
  - 文件/目录拖拽到终端（由 Terminal 侧执行路径粘贴）
  - 文件右键菜单（Reveal / Open in Terminal / Copy Path）
  - 变更文件点击后联动 `GitChangesStore` 打开 diff
  - 普通文件只读预览（二进制文件提示、大文件截断、轻量语法高亮）
- 应用层联动：
  - `openOwlApp` 注入 `ProjectStore` / `FileExplorerStore`
  - active project 变化时同步刷新 Git 面板仓库和文件树上下文

## 验证

- [x] `xcodegen generate`
- [x] `xcodebuild -scheme openOwl -configuration Debug -derivedDataPath /tmp/openowl-derived build`
- [ ] 运行时手测（Xcode Cmd+R）待完成：
  - 项目切换时 File/Git 上下文同步
  - 变更文件跳转 Diff
  - 右键菜单动作行为
  - 文件预览与性能体验

## 完成标准

- [x] 侧边栏能浏览文件树
- [x] 文件有 git 状态颜色
- [x] 能管理多个项目
