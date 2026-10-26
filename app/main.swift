import AppKit
import SwiftUI
import Foundation

let base = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support/PersonalWorkspace")
struct Snapshot: Codable {
    var schemaVersion: Int
    var syncedAt: String
    var spreadsheetURL: String
    var tables: [String:[[String]]]
}
final class Model: ObservableObject {
    let dailyTimer=DailyTimer(directory:base.appendingPathComponent("timer",isDirectory:true))
    let checks=PlanChecks(directory:base.appendingPathComponent("checks",isDirectory:true))
    @Published var layoutSize=CGSize(width:420,height:900)
    var visualBottomFromScreenTop:CGFloat=0
    @Published var data: Snapshot?
    @Published var error: String?
    var watcher: DispatchSourceFileSystemObject?
    var activePage="board"
    var dayTimer:Timer?
    func start() {
        dailyTimer.onChange={[weak self] in self?.exportProgress()}
        checks.onChange={[weak self] in self?.exportProgress()}
        reload()
        exportProgress()
        scheduleDayChange()
        NSWorkspace.shared.notificationCenter.addObserver(forName:NSWorkspace.didWakeNotification,object:nil,queue:.main) { [weak self] _ in self?.objectWillChange.send();self?.scheduleDayChange() }
        let fd = open(base.path, O_EVTONLY)
        guard fd >= 0 else {error="数据目录不可读"; return}
        let w = DispatchSource.makeFileSystemObjectSource(fileDescriptor:fd,eventMask:[.write,.rename],queue:.main)
        w.setEventHandler { [weak self] in self?.reload() }
        w.setCancelHandler { close(fd) }; watcher=w; w.resume()
        NotificationCenter.default.addObserver(forName:.NSCalendarDayChanged,object:nil,queue:.main) { [weak self] _ in self?.objectWillChange.send() }
    }
    func scheduleDayChange() {
        dayTimer?.invalidate()
        var calendar=Calendar(identifier:.gregorian);calendar.timeZone=TimeZone(identifier:"Europe/London")!
        let next=calendar.date(byAdding:.day,value:1,to:calendar.startOfDay(for:Date()))!
        dayTimer=Timer.scheduledTimer(withTimeInterval:max(1,next.timeIntervalSinceNow),repeats:false) { [weak self] _ in self?.objectWillChange.send();self?.scheduleDayChange() }
    }
    func reload() {
        do {
            let next=try JSONDecoder().decode(Snapshot.self,from:Data(contentsOf:base.appendingPathComponent("snapshot.json")))
            guard next.schemaVersion==1, ["Projects","Tasks","Daily Plan","Activity Log"].allSatisfy({next.tables[$0] != nil}) else {throw CocoaError(.fileReadCorruptFile)}
            data=next;error=nil
        } catch {self.error="同步文件不可用，保留上次数据"}
        writeDiagnostics()
    }
    func rows(_ name:String)->[[String]] {Array((data?.tables[name] ?? []).dropFirst())}
    // 给晚间汇报的进度文件：~/Personal Workspace/logs/today-progress.json
    // 内容为今天在看板上点「完成」的计划块，以及今日计时器的累计时长。只写这个文件，不碰 workspace.json。
    func exportProgress() {
        let now=Date()
        let iso=ISO8601DateFormatter();iso.timeZone=TimeZone(identifier:"Europe/London")
        let today=londonDay()
        let prefix="D"+today.replacingOccurrences(of:"-",with:"")
        let plans=rows("Daily Plan")
        let done:[[String:Any]]=checks.done.filter{$0.hasPrefix(prefix)}.sorted().map { id in
            let r=plans.first{cell($0,0)==id} ?? []
            return ["planID":id,"taskID":cell(r,2),"projectID":cell(r,3),"task":cell(r,4),"plannedMinutes":cell(r,5),"markedAt":checks.markedAt[id].map{iso.string(from:$0)} ?? ""]
        }
        let t=dailyTimer.state
        let elapsed=t.elapsed(at:now)
        var timer:[String:Any]=["workDay":t.workDay,"accumulatedSeconds":Int(t.accumulated.rounded(.down)),"running":t.running,"elapsedSecondsAtWrite":Int(elapsed.rounded(.down)),"elapsedAtWrite":String(DailyTimerState.display(elapsed).prefix(8))]
        if let started=t.startedAt {timer["startedAt"]=iso.string(from:started)}
        let obj:[String:Any]=["schemaVersion":1,"date":today,"writtenAt":iso.string(from:now),
            "note":"用户在桌面看板上点击标记的完成块与今日计时；running 为 true 时，当前时长 = accumulatedSeconds + (现在 − startedAt)",
            "completedPlans":done,"timer":timer]
        let dir=FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Personal Workspace/logs",isDirectory:true)
        guard let bytes=try? JSONSerialization.data(withJSONObject:obj,options:[.prettyPrinted,.sortedKeys]) else {return}
        try? FileManager.default.createDirectory(at:dir,withIntermediateDirectories:true)
        try? bytes.write(to:dir.appendingPathComponent("today-progress.json"),options:.atomic)
    }
    func writeDiagnostics() {
        let timeline=DDLState(tables:data?.tables ?? [:])
        let obj:[String:Any] = ["activeDesktopPage":activePage,"desktopInteraction":"aboveDesktopIcons","timelineTaskCount":timeline.tasks.count,"timelineInvalidDates":timeline.invalidDates,"timelineStats":["overdue":timeline.overdue,"within7":timeline.within(7),"within30":timeline.within(30),"high":timeline.high],"syncedAt":data?.syncedAt ?? "", "error":error ?? "", "projectCount":rows("Projects").count,"taskCount":rows("Tasks").count,"dailyPlan":rows("Daily Plan"),"diagnosticScope":"desktopViewerOnly","networkAccess":false,"remoteWriteAccess":false,"scheduledPlanning":false,"monitoring":false,"reminders":false,"panelWidth":layoutSize.width,"panelHeight":layoutSize.height,"layoutMode":"vertical","visualBottomFromScreenTop":visualBottomFromScreenTop]
        if let bytes=try? JSONSerialization.data(withJSONObject:obj,options:[.prettyPrinted,.sortedKeys]) {let url=base.appendingPathComponent("diagnostics.json");if (try? Data(contentsOf:url)) != bytes {try? bytes.write(to:url,options:.atomic)}}
    }
}
func cell(_ row:[String],_ index:Int)->String {index<row.count ? row[index] : ""}
func londonDay()->String {let f=DateFormatter();f.timeZone=TimeZone(identifier:"Europe/London");f.dateFormat="yyyy-MM-dd";return f.string(from:Date())}
struct Glass:NSViewRepresentable {
    func makeNSView(context:Context)->NSVisualEffectView {
        let v=NSVisualEffectView();v.material = .sidebar;v.blendingMode = .behindWindow;v.state = .active;v.wantsLayer=true;v.layer?.cornerRadius=22;v.layer?.masksToBounds=true;return v
    }
    func updateNSView(_ v:NSVisualEffectView,context:Context) {}
}
struct Card<Content:View>:View {
    let title:String
    let subtitle:String
    let content:Content
    let accessory:AnyView?
    init(_ title:String,subtitle:String="",accessory:AnyView?=nil,@ViewBuilder content:()->Content) {self.title=title;self.subtitle=subtitle;self.accessory=accessory;self.content=content()}
    var body:some View {
        VStack(alignment:.leading,spacing:8) {
            HStack(alignment:.center,spacing:8) {
                Text(title).font(.system(size:12,weight:.medium)).foregroundStyle(.secondary)
                if !subtitle.isEmpty {Text(subtitle).font(.system(size:12)).foregroundStyle(.secondary).lineLimit(1)}
                Spacer(minLength:4)
                if let accessory=accessory {accessory}
            }.frame(minHeight:22)
            content
            Spacer(minLength:0)
        }.padding(.horizontal,16).padding(.vertical,10).frame(maxWidth:.infinity,maxHeight:.infinity,alignment:.topLeading)
        .background(Glass()).overlay(RoundedRectangle(cornerRadius:22).stroke(.primary.opacity(0.07),lineWidth:1))
    }
}
struct ProjectProgress {
    let completed:Int
    let total:Int
    var fraction:Double {total>0 ? Double(completed)/Double(total):0}
    var percentage:String {total>0 ? "\(Int((fraction*100).rounded()))%":"—"}
}
func activePlans(_ plans:[[String]],tasks:[[String]])->[[String]] {
    let unfinished=Set(tasks.filter{!["已完成","取消"].contains(cell($0,3))}.map{cell($0,0)})
    return plans.filter{!["已完成","取消"].contains(cell($0,6)) && unfinished.contains(cell($0,2))}
}
// 任务池排序：优先级 → 截止日期（无日期排后）→ Task ID
func sortedBacklog(_ tasks:[[String]],plans:[[String]])->[[String]] {
    let rank=["高":0,"中":1,"低":2]
    return unplannedTasks(tasks,plans:plans).sorted {
        let a=rank[cell($0,4)] ?? 3,b=rank[cell($1,4)] ?? 3
        if a != b {return a<b}
        let ad=cell($0,6).isEmpty ? "9999":cell($0,6),bd=cell($1,6).isEmpty ? "9999":cell($1,6)
        if ad != bd {return ad<bd}
        return cell($0,0)<cell($1,0)
    }
}
func unplannedTasks(_ tasks:[[String]],plans:[[String]])->[[String]] {
    let planned=Set(activePlans(plans,tasks:tasks).map{cell($0,2)})
    return tasks.filter{!["已完成","取消"].contains(cell($0,3)) && !cell($0,0).hasPrefix("SYS") && !planned.contains(cell($0,0))}
}
struct CompletionBar:View {
    let progress:ProjectProgress
    let tint:Color
    var body:some View {
        GeometryReader { geometry in
            ZStack(alignment:.leading) {
                Capsule().fill(BoardStyle.track)
                Capsule().fill(tint).frame(width:geometry.size.width*progress.fraction)
            }
        }.frame(height:5)
        .accessibilityLabel("已登记任务完成率")
        .accessibilityValue(progress.total>0 ? "已确认完成\(progress.completed)项，共\(progress.total)项，\(progress.percentage)":"尚无任务")
    }
}
struct TagChip:View {
    let text:String
    var body:some View {
        Text(text).font(.system(size:9,weight:.medium)).foregroundStyle(.secondary).fixedSize()
            .padding(.horizontal,5).padding(.vertical,1)
            .overlay(RoundedRectangle(cornerRadius:4).stroke(Color.secondary.opacity(0.7),style:StrokeStyle(lineWidth:0.8,dash:[2,2])))
    }
}
struct Board:View {
    @ObservedObject var model:Model
    @ObservedObject var checks:PlanChecks
    var showTimeline:(()->Void)?
    var showPool:(()->Void)?
    @Environment(\.colorScheme) var scheme
    init(model:Model,showTimeline:(()->Void)?=nil,showPool:(()->Void)?=nil) {
        _model=ObservedObject(wrappedValue:model);_checks=ObservedObject(wrappedValue:model.checks);self.showTimeline=showTimeline;self.showPool=showPool
    }
    var tasks:[[String]] {model.rows("Tasks")}
    var taskByID:[String:[String]] {Dictionary(tasks.map{(cell($0,0),$0)},uniquingKeysWith:{a,_ in a})}
    var projects:[[String]] {model.rows("Projects").sorted{cell($0,0)<cell($1,0)}}
    var scheduled:[[String]] {activePlans(model.rows("Daily Plan"),tasks:tasks)}
    var taskStatus:[String:String] {Dictionary(tasks.map{(cell($0,0),cell($0,3))},uniquingKeysWith:{a,_ in a})}
    // 今天的全部计划块（含数据库里已完成的），取消的不显示
    var todayRows:[[String]] {
        let status=taskStatus
        return model.rows("Daily Plan").filter{cell($0,1)==londonDay() && cell($0,6) != "取消" && status[cell($0,2)] != "取消"}
    }
    func doneInDatabase(_ r:[String],_ status:[String:String])->Bool {cell(r,6)=="已完成" || status[cell(r,2)]=="已完成"}
    var otherScheduled:Int {scheduled.filter{cell($0,1) != londonDay()}.count}
    var todayPrefix:String {"D"+londonDay().replacingOccurrences(of:"-",with:"")}
    func progress(for project:[String])->ProjectProgress {
        let rows=tasks.filter{cell($0,1)==cell(project,0) && !cell($0,0).hasPrefix("SYS") && cell($0,3) != "取消"}
        return ProjectProgress(completed:rows.filter{cell($0,3)=="已完成"}.count,total:rows.count)
    }
    func headerDate()->String {
        let f=DateFormatter();f.timeZone=TimeZone(identifier:"Europe/London");f.locale=Locale(identifier:"zh_CN");f.dateFormat="M月d日 EEE";return f.string(from:Date())
    }
    func projectName(_ p:[String])->String {
        ["P01":"硕士申请","P02":"课程与论文","P03":"求职与实习","P04":"AI 作品集"][cell(p,0)] ?? cell(p,1)
    }
    var syncText:String {
        if let error=model.error {return error}
        guard let stamp=model.data?.syncedAt,stamp.count>=16 else{return "尚无数据"}
        return "数据更新 "+stamp.dropFirst(5).prefix(11).replacingOccurrences(of:"-",with:"/")
    }
    var backlog:[[String]] {sortedBacklog(tasks,plans:model.rows("Daily Plan"))}
    func minutes(_ row:[String],_ index:Int)->Int {Int(cell(row,index).trimmingCharacters(in:.whitespaces)) ?? 0}
    func shortDue(_ raw:String)->String {DDLDay(String(raw.prefix(10))).map{String(format:"%02d/%02d",$0.month,$0.day)} ?? "—"}

    // 高度分配：今日安排占剩余空间
    // 高度按优先级分配：今日安排先放下全部任务 → 截止日期至少 3 行 → 任务池用剩余空间
    static let todayRowH:CGFloat=26, ddlRowH:CGFloat=20, poolRowH:CGFloat=26
    var contentHeight:CGFloat {model.layoutSize.height-16-30}
    var projectHeight:CGFloat {100}
    var cardChrome:CGFloat {20+22+8}                       // 上下内边距 + 标题行 + 间距
    var todayNeeded:CGFloat {cardChrome+24+8+CGFloat(max(1,todayRows.count))*Self.todayRowH}
    var ddlMin:CGFloat {cardChrome+3*Self.ddlRowH}
    var ddlMax:CGFloat {cardChrome+7*Self.ddlRowH}
    var poolMin:CGFloat {20+22}
    var available:CGFloat {contentHeight-projectHeight}
    var plannedHeight:CGFloat {max(cardChrome+32+Self.todayRowH,min(todayNeeded,available-ddlMin-poolMin))}
    var poolHeight:CGFloat {poolMin}                        // 任务池压缩为一行摘要
    var ddlHeight:CGFloat {max(ddlMin,available-plannedHeight-poolHeight)}
    var visibleTodayCount:Int {max(1,Int((plannedHeight-cardChrome-32)/Self.todayRowH))}
    var visibleDeadlineCount:Int {max(1,min(12,Int((ddlHeight-cardChrome)/Self.ddlRowH)))}
    var visibleBacklogCount:Int {max(0,min(4,Int((poolHeight-cardChrome)/Self.poolRowH)))}

    var body:some View {
        VStack(alignment:.leading,spacing:10) {
            todayCard.frame(height:plannedHeight)
            deadlineCard.frame(height:ddlHeight)
            poolCard.frame(height:poolHeight)
            projectCard.frame(height:projectHeight)
        }.padding(8).frame(width:model.layoutSize.width,height:model.layoutSize.height)
        .onChange(of:scheme) { next in recordAppearance(next) }
        .onAppear{recordAppearance(scheme)}
    }

    // MARK: 今日安排
    var todayCard:some View {
        let rows=todayRows
        let status=taskStatus
        let total=rows.reduce(0){$0+minutes($1,5)}
        let doneRows=rows.filter{doneInDatabase($0,status) || checks.isDone(cell($0,0))}
        let remaining=total-doneRows.reduce(0){$0+minutes($1,5)}
        let split=["P01","P02","P03","P04"].map{id in (id,rows.filter{cell($0,3)==id}.reduce(0){$0+minutes($1,5)})}.filter{$0.1>0}
        return Card("今日安排",subtitle:headerDate(),accessory:AnyView(DailyTimerButton(timer:model.dailyTimer))) {
            if rows.isEmpty {
                Text("今天没有已排计划").font(.system(size:12)).foregroundStyle(.secondary)
            } else {
                VStack(alignment:.leading,spacing:4) {
                    HStack(alignment:.firstTextBaseline) {
                        (Text("\(doneRows.count)").font(.system(size:12,weight:.semibold)).foregroundColor(.primary)+Text(" / \(rows.count) 已完成").font(.system(size:10)))
                            .monospacedDigit().foregroundStyle(.secondary)
                        Spacer()
                        Text("计划 \(BoardStyle.minutes(total)) · 剩余 \(BoardStyle.minutes(remaining))").font(.system(size:10)).monospacedDigit().foregroundStyle(.secondary)
                    }
                    GeometryReader { g in
                        HStack(spacing:2) {
                            ForEach(split.indices,id:\.self) { i in
                                Rectangle().fill(BoardStyle.dot(split[i].0)).frame(width:max(2,(g.size.width-CGFloat(split.count-1)*2)*CGFloat(split[i].1)/CGFloat(max(total,1))))
                            }
                        }.clipShape(Capsule())
                    }.frame(height:4)
                    .accessibilityLabel("今日时间按项目分配")
                }
                VStack(alignment:.leading,spacing:0) {
                    ForEach(Array(rows.prefix(visibleTodayCount).enumerated()),id:\.offset) { _,r in todayRow(r,locked:doneInDatabase(r,status)) }
                }
            }
        }
    }
    func todayRow(_ r:[String],locked:Bool)->some View {
        let planID=cell(r,0)
        let done=locked || checks.isDone(planID)
        let title=TitleFormatter.display(id:cell(r,2),raw:cell(r,4))
        let status=cell(r,6)
        return Button {checks.toggle(planID,keepPrefix:todayPrefix)} label: {
            HStack(alignment:.center,spacing:10) {
                Circle().fill(BoardStyle.dot(cell(r,3))).frame(width:8,height:8).opacity(done ? 0.35:1)
                Text(title.text).font(.system(size:12,weight:.medium)).strikethrough(done,color:.secondary)
                    .lineLimit(1).truncationMode(.tail).foregroundStyle(done ? Color.secondary:Color.primary)
                Spacer(minLength:6)
                if !done && ["进行中","受阻"].contains(status) {
                    Text(status).font(.system(size:10,weight:.medium)).foregroundStyle(status=="受阻" ? BoardStyle.urgentFG:BoardStyle.ink(cell(r,3)))
                }
                Text(BoardStyle.minutes(minutes(r,5))).font(.system(size:10)).monospacedDigit().strikethrough(done,color:.secondary).foregroundStyle(.secondary)
            }.frame(height:Self.todayRowH).contentShape(Rectangle())
            .overlay(Rectangle().fill(BoardStyle.rule).frame(height:1),alignment:.top)
        }.buttonStyle(.plain).disabled(locked)
        .help(cell(r,4)+(locked ? "\n\n数据库中已完成":"\n\n点击标记完成 / 取消；晚间汇报会读取并写入数据库"))
        .accessibilityLabel(title.text+(done ? "，已完成":""))
        .accessibilityHint(locked ? "":"点击切换完成状态")
    }

    // MARK: 截止日期
    var deadlineCard:some View {
        let state=DDLState(tables:model.data?.tables ?? [:])
        let items=Array(state.tasks.prefix(visibleDeadlineCount))
        return Card("截止日期",subtitle:"7 天内 \(state.within(7)) · 30 天内 \(state.within(30))",accessory:showTimeline.map{action in AnyView(
            Button("时间线 ›",action:action).font(.system(size:10)).buttonStyle(.bordered).controlSize(.small).help("在桌面卡片中查看完整 DDL 时间线"))}) {
            VStack(alignment:.leading,spacing:0) {
                ForEach(Array(items.enumerated()),id:\.offset) { i,task in
                    deadlineRow(task,today:state.today,showDate:i==0 || items[i-1].due != task.due)
                }
                if state.tasks.isEmpty {Text("暂无未完成且有截止日期的任务").font(.system(size:12)).foregroundStyle(.secondary)}
            }
        }
    }
    func deadlineRow(_ task:DDLTask,today:DDLDay,showDate:Bool)->some View {
        let due=task.due!
        let left=today.distance(to:due)
        let title=TitleFormatter.display(id:task.id,raw:task.name)
        let label=left<0 ? "逾期\(-left)天":(left==0 ? "今天":"\(left)天")
        let urgent=left<=5,soon=left<=7
        return HStack(alignment:.center,spacing:8) {
            HStack(spacing:4) {
                Text(String(format:"%02d/%02d",due.month,due.day)).font(.system(size:10,weight:.medium,design:.monospaced))
                Text(due.weekday).font(.system(size:10)).foregroundStyle(.secondary)
            }.monospacedDigit().frame(width:62,alignment:.leading).opacity(showDate ? 1:0)
            Circle().fill(BoardStyle.dot(task.projectID)).frame(width:6,height:6)
            Text(title.text).font(.system(size:12,weight:.medium)).lineLimit(1).truncationMode(.tail)
            Spacer(minLength:4)
            ForEach(title.tags,id:\.self) {TagChip(text:$0)}
            Text(label).font(.system(size:10,weight:.semibold)).monospacedDigit().fixedSize()
                .padding(.horizontal,5).padding(.vertical,1).frame(minWidth:28)
                .background(Capsule().fill(urgent ? BoardStyle.urgentBG:(soon ? BoardStyle.soonBG:BoardStyle.neutralBG)))
                .foregroundStyle(urgent ? BoardStyle.urgentFG:(soon ? BoardStyle.soonFG:Color.secondary))
        }.frame(height:Self.ddlRowH).contentShape(Rectangle())
        .help(task.tooltip)
    }

    // MARK: 任务池（一行摘要；完整列表见悬停提示）
    var poolCard:some View {
        let rows=backlog
        let high=rows.filter{cell($0,4)=="高"}.count
        let earliest=rows.compactMap{DDLDay(String(cell($0,6).prefix(10)))}.min()
        let preview=rows.prefix(8).map{"· "+TitleFormatter.display(id:cell($0,0),raw:cell($0,2)).text+(cell($0,6).isEmpty ? "":"  "+shortDue(cell($0,6)))}.joined(separator:"\n")
        return HStack(alignment:.center,spacing:8) {
            Text("任务池").font(.system(size:12,weight:.medium)).foregroundStyle(.secondary)
            Text("未排期 \(rows.count) 项").font(.system(size:10)).foregroundStyle(.secondary)
            Text("高优先 \(high)").font(.system(size:10,weight:.medium)).foregroundStyle(high>0 ? BoardStyle.urgentFG:Color.secondary)
            Spacer(minLength:4)
            if let d=earliest {Text("最早截止 "+String(format:"%02d/%02d",d.month,d.day)).font(.system(size:10)).monospacedDigit().foregroundStyle(.secondary)}
            if let action=showPool {Button("全部 ›",action:action).font(.system(size:10)).buttonStyle(.bordered).controlSize(.small).help("在桌面卡片中查看完整任务池")}
        }.padding(.horizontal,16).frame(maxWidth:.infinity,maxHeight:.infinity)
        .background(Glass()).overlay(RoundedRectangle(cornerRadius:22).stroke(.primary.opacity(0.07),lineWidth:1))
        .help(rows.isEmpty ? "没有未排期任务":"按优先级排在前面的未排期任务：\n"+preview)
    }

    // MARK: 项目进度
    var projectCard:some View {
        VStack(alignment:.leading,spacing:8) {
            LazyVGrid(columns:[GridItem(.flexible(),spacing:20),GridItem(.flexible())],alignment:.leading,spacing:10) {
                ForEach(Array(projects.prefix(4).enumerated()),id:\.offset) { _,p in
                    let completion=progress(for:p)
                    VStack(alignment:.leading,spacing:4) {
                        HStack(alignment:.firstTextBaseline,spacing:4) {
                            Text(projectName(p)).font(.system(size:12,weight:.medium)).lineLimit(1)
                            Spacer(minLength:2)
                            Text("\(completion.completed)/\(completion.total)").font(.system(size:10)).monospacedDigit().foregroundStyle(.secondary)
                            Text(completion.percentage).font(.system(size:10,weight:.medium,design:.monospaced)).monospacedDigit().foregroundStyle(BoardStyle.ink(cell(p,0)))
                        }
                        CompletionBar(progress:completion,tint:BoardStyle.dot(cell(p,0)))
                    }.help(cell(p,1)+"\n"+cell(p,3))
                }
            }
            Spacer(minLength:0)
            HStack {
                Text(syncText).foregroundStyle(model.error == nil ? Color.secondary:Color.orange)
                Spacer()
                Text("只读看板")
            }.font(.system(size:10)).foregroundStyle(.secondary)
        }.padding(.horizontal,16).padding(.vertical,10)
        .background(Glass()).overlay(RoundedRectangle(cornerRadius:22).stroke(.primary.opacity(0.07),lineWidth:1))
    }
    func recordAppearance(_ appearance:ColorScheme) {try? (appearance == .dark ? "dark":"light").write(to:base.appendingPathComponent("appearance.txt"),atomically:true,encoding:.utf8)}
}

final class DesktopWindow:NSWindow {
    override var canBecomeKey:Bool {true}
    override var canBecomeMain:Bool {false}
    override func accessibilityPerformRaise()->Bool {
        level = .normal
        makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps:true)
        return true
    }
}
final class DesktopHost:NSHostingView<DesktopRoot> {
    override func acceptsFirstMouse(for event:NSEvent?)->Bool {true}
}
final class Delegate:NSObject,NSApplicationDelegate {
    let model=Model(); var window:DesktopWindow!; var status:NSStatusItem!
    func applicationDidFinishLaunching(_ notification:Notification) {
        NSApp.setActivationPolicy(.accessory)
        model.start()
        window=DesktopWindow(contentRect:NSRect(x:0,y:0,width:420,height:900),styleMask:.borderless,backing:.buffered,defer:false)
        window.title="Personal Workspace V1.0";window.isOpaque=false;window.backgroundColor = .clear;window.hasShadow=false;window.ignoresMouseEvents=false;window.acceptsMouseMovedEvents=true;window.isMovableByWindowBackground=false
        // Above Finder desktop icons so pointer events reach the cards; below normal app windows.
        window.level=NSWindow.Level(rawValue:Int(CGWindowLevelForKey(.desktopIconWindow))+1)
        window.setAccessibilitySubrole(.standardWindow)
        window.collectionBehavior=[.canJoinAllSpaces,.stationary,.ignoresCycle];window.hidesOnDeactivate=false
        let host=DesktopHost(rootView:DesktopRoot(model:model));host.wantsLayer=true;host.layer?.backgroundColor=NSColor.clear.cgColor
        window.contentView=host;position();window.orderFrontRegardless()
        NotificationCenter.default.addObserver(forName:NSWindow.didChangeOcclusionStateNotification,object:window,queue:.main) { [weak self] _ in
            guard let self=self else {return}
            self.model.dailyTimer.displayVisible=self.window.isVisible && self.window.occlusionState.contains(.visible)
        }
        NotificationCenter.default.addObserver(forName:NSApplication.didBecomeActiveNotification,object:nil,queue:.main) { [weak self] _ in self?.window.level = .normal }
        NotificationCenter.default.addObserver(forName:NSApplication.didResignActiveNotification,object:nil,queue:.main) { [weak self] _ in
            self?.window.level=NSWindow.Level(rawValue:Int(CGWindowLevelForKey(.desktopIconWindow))+1)
        }
        NotificationCenter.default.addObserver(forName:NSApplication.didChangeScreenParametersNotification,object:nil,queue:.main){[weak self]_ in self?.position()}
        status=NSStatusBar.system.statusItem(withLength:NSStatusItem.squareLength)
        status.button?.image=NSImage(systemSymbolName:"square.grid.2x2",accessibilityDescription:"看板控制：打开数据库、刷新面板、显示或隐藏、退出")
        let menu=NSMenu()
        let info=NSMenuItem(title:"看板 · 只读显示",action:nil,keyEquivalent:"");info.isEnabled=false;menu.addItem(info)
        for (title,action) in [("DDL 时间线",#selector(showTimeline)),("打开任务数据库",#selector(openSheet)),("刷新面板（本地数据）",#selector(reload)),("显示 / 隐藏看板",#selector(toggle)),("退出看板",#selector(quit))] {let i=NSMenuItem(title:title,action:action,keyEquivalent:"");i.target=self;menu.addItem(i)}
        status.button?.toolTip="看板控制"
        status.menu=menu
    }
    func position(){
        guard let screen=NSScreen.main else{return}
        let frame=screen.visibleFrame
        // Desktop filename bottom measured at y=1608 in a 1912px CUA desktop capture.
        let labelBottom=screen.frame.minY+screen.frame.height*(304.0/1912.0)
        let originY=max(frame.minY+8,labelBottom-8)
        let size=CGSize(width:min(420,max(360,frame.width*0.30)),height:max(540,frame.maxY-8-originY))
        model.layoutSize=size
        model.visualBottomFromScreenTop=screen.frame.maxY-(originY+8)
        window.setContentSize(size)
        window.setFrameOrigin(NSPoint(x:frame.minX+8,y:originY))
        model.writeDiagnostics()
    }
    @objc func showTimeline(){NotificationCenter.default.post(name:Notification.Name("PersonalWorkspace.OpenTimeline"),object:nil);window.orderFrontRegardless()}
    @objc func openSheet(){let url=FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Personal Workspace/data/workspace.json");NSWorkspace.shared.open(url)}
    @objc func reload(){model.reload()}
    @objc func toggle(){if window.isVisible{window.orderOut(nil)}else{window.orderFrontRegardless()}}
    @objc func quit(){NSApp.terminate(nil)}
}
if CommandLine.arguments.count==3 && CommandLine.arguments[1]=="--import-snapshot" {
    do {
        let incoming=try Data(contentsOf:URL(fileURLWithPath:CommandLine.arguments[2]))
        guard incoming.count<5_000_000 else {throw CocoaError(.fileReadTooLarge)}
        let s=try JSONDecoder().decode(Snapshot.self,from:incoming)
        let required=["Projects":7,"Tasks":8,"Daily Plan":8,"Activity Log":6]
        guard s.schemaVersion==1, s.spreadsheetURL=="https://docs.google.com/spreadsheets/d/YOUR_SHEET_ID/edit" else {throw CocoaError(.fileReadCorruptFile)}
        for (name,width) in required {
            guard let rows=s.tables[name],!rows.isEmpty,rows.count<=10000,rows.allSatisfy({$0.count==width}),rows.dropFirst().allSatisfy({!cell($0,0).isEmpty}),Set(rows.dropFirst().map{cell($0,0)}).count==rows.count-1 else {throw CocoaError(.fileReadCorruptFile)}
        }
        guard Set(s.tables["Projects"]!.dropFirst().map({cell($0,0)}))==Set(["P01","P02","P03","P04"]) else {throw CocoaError(.fileReadCorruptFile)}
        let projects=Set(s.tables["Projects"]!.dropFirst().map{cell($0,0)})
        let tasks=Set(s.tables["Tasks"]!.dropFirst().map{cell($0,0)})
        let taskProjects=Dictionary(uniqueKeysWithValues:s.tables["Tasks"]!.dropFirst().map{(cell($0,0),cell($0,1))})
        guard s.tables["Tasks"]!.dropFirst().allSatisfy({projects.contains(cell($0,1))}),s.tables["Daily Plan"]!.dropFirst().allSatisfy({tasks.contains(cell($0,2)) && projects.contains(cell($0,3))}) else {throw CocoaError(.fileReadCorruptFile)}
        guard s.tables["Daily Plan"]!.dropFirst().allSatisfy({taskProjects[cell($0,2)]==cell($0,3)}) else {throw CocoaError(.fileReadCorruptFile)}
        try FileManager.default.createDirectory(at:base,withIntermediateDirectories:true,attributes:[.posixPermissions:0o700])
        let url=base.appendingPathComponent("snapshot.json")
        try incoming.write(to:url,options:.atomic)
        try FileManager.default.setAttributes([.posixPermissions:0o444],ofItemAtPath:url.path)
        print("Read-only snapshot imported: \(s.tables["Projects"]!.count-1) projects; \(s.tables["Tasks"]!.count-1) tasks; \(s.syncedAt)")
        exit(0)
    } catch {fputs("Snapshot rejected; previous data preserved: \(error)\n",stderr);exit(1)}
}
let app=NSApplication.shared
let delegate=Delegate();app.delegate=delegate;app.run()
