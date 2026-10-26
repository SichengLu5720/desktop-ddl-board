# 桌面 DDL 时间线

源数据仍为 `~/Personal Workspace/data/workspace.json`，由原有 `bin/apply.sh` 导入到应用快照。DDL 模块不写任务、不改 schema、不请求网络。新增计时器仅保存独立本机计时记录。

## 入口

在桌面 DDL 卡片右上角点「DDL 时间线」，原位切换为时间线卡片。右上角「返回看板」回到原概览。图表圆点和按周清单行可进入同一套卡片里的任务详情。

视图为窄幅桌面卡片，纵向滚动查看四个模块；分布图和工时图可横向滚动查看完整日期范围。项目配色与原看板一致。

## 文件

- `main.swift`：原生桌面窗口、快照监听、原看板和 CLI 导入器；增加 DDL 入口和只读诊断。
- `TimelineData.swift`：日期、过滤、统计、周工时与点位错开逻辑。
- `TimelineViews.swift`：磨砂时间线卡片、图表、周清单和详情。
- `DailyTimerState.swift`：伦敦07:00工作日、累计计时与重启恢复。
- `DailyTimerView.swift`：紧凑的开始/暂停按钮与一次性每日重置调度。
- `tests/timer/main.swift`：22项计时、跨日、休眠恢复与夏令时检查。
- `tests/main.swift`：28项日期/过滤/工时/点位检查；不操作真实数据库。
- `build.sh`：仅编译到 `.build/PersonalWorkspace`，不会安装或更改数据。

## 编译和测试

```sh
/bin/bash "$HOME/Personal Workspace/app/build.sh"
swiftc "$HOME/Personal Workspace/app/TimelineData.swift" "$HOME/Personal Workspace/app/tests/main.swift" -o "$HOME/Personal Workspace/app/.build/test-timeline"
"$HOME/Personal Workspace/app/.build/test-timeline" "$HOME/Personal Workspace/data/workspace.json"
```

维护源为本目录五份 Swift 文件。已安装的 app Resources 中另有组合成单文件的 `Workspace.swift`，以及五份原始模块副本；组合文件可按旧方式单文件编译。更新后需同步当前运行应用与登录启动器使用的已安装应用，并重新签名。

## 日期和显示口径

- 以 Europe/London 的当前日期计算，周一为一周开始；通过 date-only 运算避开夏令时的23/25小时日。
- 7天内：今天至第6天；30天内：今天至第29天；逾期不计入这两项。
- 四个数字都仅统计有合法截止日期且状态不是已完成/取消的任务。
- 待确认状态画空心点；未知估时不虚构为工时，周清单另标未估时数量。
- 日期轴从本周一到最后截止日。早于本周一的逾期任务保留在逾期统计和周清单，图下提示，不把它们错误地画在周一。空数据/全部逾期时使用本周的安全日期轴。
- 原生目录监听复用 Model；快照导入后立即刷新。另有伦敦次日零点的一次性计时器和唤醒通知，用于更新“今天”，不轮询数据。

看板为支持按钮、悬停与滚动，现接收鼠标交互；原窗口大小、位置保留。窗口闲置时位于 Finder 桌面图标之上、普通应用窗口之下；激活时进入普通窗口层以支持键盘与鼠标交互，切换到其他应用后自动回到桌面层。所有原始任务内容在详情中按纯文本显示，不自动打开来源链接。

## 今日计时器

「今日安排」右上角的播放/暂停按钮控制累计时长。每天 Europe/London 07:00 归零并暂停；07:00之前属于前一计时日。关闭/重启保留计时进度，计时中休眠也按真实经过时间累计；若休眠或退出期间经过07:00，下次唤醒/启动时归零暂停。

记录保存至 `~/Library/Application Support/PersonalWorkspace/timer/state.json`（权限0600），不写任务数据库或 Activity Log；开始、暂停和跨日时才写盘。显示格式为 HH:mm:ss.SS，精确到百分之一秒；运行时最多30帧/秒，仅更新小型计时控件，不发布逐帧 Model 变更、不重读快照、不重算 DDL 图表。暂停时不进行持续显示刷新；窗口隐藏/完全遮挡时也停止持续显示刷新。每日重置使用一个一次性计时器，另在唤醒和时钟变化时校正。无需新增后台程序或规划自动化。

测试：

```sh
swiftc "$HOME/Personal Workspace/app/DailyTimerState.swift" "$HOME/Personal Workspace/app/tests/timer/main.swift" -o "$HOME/Personal Workspace/app/.build/test-timer"
"$HOME/Personal Workspace/app/.build/test-timer"
```

## 看板 v1.1（可读性改版）

- 卡片顺序：今日安排 → 截止日期 → 任务池 → 项目进度；正文 12–14pt，最小 10–11pt。
- 今日安排：显示完成数、计划/剩余时长、按项目分色的时间条与每项时长。**点击任务行标记完成/取消**（变灰划线）。看板不写 `workspace.json`；每次标记或计时开始/暂停时写出 `~/Personal Workspace/logs/today-progress.json`（完成的计划块 + 今日计时），晚间汇报读取后写入数据库（规则见 `AGENTS.md` EVENING 第 3 步）。数据库里已完成的块显示为完成且不可再点。
- 截止日期：逐条显示，同日只写一次日期；剩余天数 ≤5 天红色、≤7 天橙色，逾期显示「逾期N天」。
- 深浅色：卡片沿用系统磨砂材质，文字与标签使用 `BoardStyle.swift` 中的浅/深双色。
- 短标题：`TitleFormatter.swift`，规则按顺序执行——0 手动命名（Task ID）优先；1 全角符号归一；2 课程代码→「课程 · 」；3 括号内的截止性质提取为标签（准备日/RAA/普通/待核/待公布/视情况），括号移出标题；4「主题：细节」只留主题，细节首句 ≤8 字或主题 <4 字时接「 · 首句」；5 无冒号且超过 18 字时保留第一个逗号前；6 去掉 ≥7 字的「并……」后续动作；7 中文与字母数字间加空格。被省略的原文在悬停提示中完整显示。
- 一键更新：`/bin/bash "$HOME/Personal Workspace/app/update.sh"`（编译、跑三组测试、备份并替换已安装程序、重新签名、重启）。
