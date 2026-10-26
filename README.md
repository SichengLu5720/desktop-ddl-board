# Desktop DDL Board

一个常驻 macOS 桌面的个人任务看板（SwiftUI + AppKit），配合 AI Agent 做每日排程与复盘。数据全部在本机一个 JSON 文件里：不联网、不轮询、不需要密钥。

## 它解决什么

学业、申请、求职、作品集四条线同时推进时，截止日期散落在邮件、课程平台和笔记里。这个项目把它们收进一张表，由 Agent 早晚各运行一次来维护，桌面看板只负责“让我一眼看到今天该做什么、什么快到期”。

## 架构

```
AI Agent（早 / 晚定时运行，规则见 AGENTS.template.md）
   │  读邮件和课程平台（只读）→ 最小变更 → 写回
   ▼
data/workspace.json          ← 唯一数据源：Projects / Tasks / Daily Plan / Activity Log
   │  launchd 监听文件变化
   ▼
bin/apply.sh → 看板自带的校验导入（--import-snapshot）→ 只读快照
   │  目录监听，导入后立即刷新
   ▼
桌面看板（app/）
   │  点击「完成」、开始/暂停计时
   ▼
logs/today-progress.json     → 晚间汇报读取，写回数据库
```

看板本身永远不写 `workspace.json`；写入只由 Agent 完成，并且每次写入都要经过校验导入。

## 功能

- **今日安排**：完成数、计划/剩余时长、按项目分色的时间条；点击任务标记完成（只在本机标记，晚间由 Agent 同步）；每日 07:00 重置的计时器。
- **截止日期**：逐条显示剩余天数，≤5 天红色、≤7 天橙色；准备日、RAA 等截止性质显示为标签。
- **DDL 时间线**：按项目分泳道的截止分布图、每周到期工作量、按周清单、任务详情。
- **任务池**：未排期任务按优先级分组，显示截止日期和预计时长。
- **短标题规则**：`app/TitleFormatter.swift` 按顺序执行 8 条正则规则，把长任务名缩成「动作 + 对象」，被省略的原文在悬停提示里完整保留。
- 浅色和深色模式自动切换。

## 目录

| 路径 | 说明 |
|---|---|
| `app/` | 看板源码、测试、`build.sh`（只编译）、`update.sh`（编译 → 测试 → 替换已安装程序 → 重启） |
| `bin/apply.sh` | 数据文件变化时运行：校验导入、备份、写同步状态 |
| `install.command` | 首次安装：注册 launchd 监听并同步一次 |
| `data/workspace.example.json` | 数据格式示例（四张表，表头固定） |
| `AGENTS.template.md` | Agent 规则模板：数据操作流程、早晚两种运行模式、规划规则、执行边界 |

## 使用

1. 把 `data/workspace.example.json` 复制为 `data/workspace.json`，按自己的项目和任务修改。示例里的 `spreadsheetURL` 是占位值，导入时会和 `app/main.swift` 里的值比对，两处保持一致即可。
2. 编译测试：`/bin/bash app/build.sh`；测试命令见 `app/README.md`。
3. 首次安装运行 `install.command`；之后改代码用 `/bin/bash app/update.sh` 更新。
4. 把 `AGENTS.template.md` 复制为 `AGENTS.md`，填入自己的课程、邮箱和课表，交给定时运行的 Agent 使用。

要求 macOS 13 或更高版本，以及 Xcode 命令行工具（`swiftc`）。

## 隐私

`.gitignore` 已排除真实数据、备份、日志和个人版 `AGENTS.md`。仓库里的课程代码、任务和数据都是示例。
