# AGENTS.md

Tagivy 是 AppKit 优先的 macOS 本地视频标签管理器。

## 事实在代码里

- 产品行为以当前代码和测试为准，不维护需求、设计、任务、验收或架构决策文档。
- 确认下来的行为用测试锁定（`Tests/`）；项目级规则用 `script/check_invariants.rb` 锁定。新增或改变规则时改这两处，不写文档或注释来说明。
- 用命名清楚的类型、常量和函数表达意图；注释只写代码无法表达的原因。
- 原型、调研和过程记录不进仓库。交互不确定时可以先做临时原型给用户看，确认后直接实现。
- 测试只证明它断言的内容。产品逻辑、交互和 UI 由用户验收。

运行 `ruby script/check_invariants.rb` 会逐条列出它锁定的规则。

## 工程约定

- 主窗口、视频网格、标签树、多选、拖拽、菜单和窗口行为用 AppKit；SwiftUI 只用于设置、锁屏等辅助界面。
- 数据库用系统 SQLite3。
- 扫描、媒体解析和缩略图在后台执行，UI 更新回到 MainActor。
- 防御分支、fallback 和抽象要对应真实场景、已证实的故障或明确的安全风险。

## 界面文案

- 只给用户判断当前状态和完成下一步所需的最少信息，同一事实不重复表达。
- 不暴露 Bookmark、缓存、持续访问等实现概念，除非它影响用户的判断或恢复操作。

## 验证

```bash
ruby script/check_invariants.rb
xcodebuild -project VideoTagManager.xcodeproj -scheme VideoTagManager -configuration Debug -derivedDataPath .build/DerivedData test
```

CI 在每次 push 和 PR 上运行这两项。不触碰已安装的正式 App、真实资料库和用户原始文件，测试只用合成数据。发布流程见 `docs/release.md`。

## 沟通

直接说结论，保持中立客观，从用户视角讨论产品问题。
