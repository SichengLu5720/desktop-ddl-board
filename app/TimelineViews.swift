import SwiftUI
import AppKit

enum DDLStyle {
    static func color(_ id:String)->Color {
        BoardStyle.dot(id)
    }
    static let border=Color.primary.opacity(0.07)
}
struct DDLGlassCard<Content:View>:View {
    let title:String
    let note:String
    let content:Content
    init(_ title:String,note:String="",@ViewBuilder content:()->Content) {self.title=title;self.note=note;self.content=content()}
    var body:some View {
        VStack(alignment:.leading,spacing:10) {
            if !title.isEmpty || !note.isEmpty {
                VStack(alignment:.leading,spacing:3) {
                    if !title.isEmpty {Text(title).font(.system(size:12,weight:.medium)).foregroundStyle(.secondary)}
                    if !note.isEmpty {Text(note).font(.system(size:10)).foregroundStyle(.secondary).fixedSize(horizontal:false,vertical:true)}
                }
            }
            content
        }.padding(.horizontal,16).padding(.vertical,12).frame(maxWidth:.infinity,alignment:.leading)
        .background(Glass()).overlay(RoundedRectangle(cornerRadius:22).stroke(DDLStyle.border,lineWidth:1))
    }
}
struct DDLHeader:View {
    let title:String
    let backTitle:String
    let back:()->Void
    var body:some View {
        HStack {
            Button(action:back) {Text("‹ "+backTitle).font(.system(size:10))}.buttonStyle(.bordered).controlSize(.small)
            Spacer(minLength:8)
            Text(title).font(.system(size:12,weight:.semibold))
        }.padding(.horizontal,16).padding(.vertical,10)
        .background(Glass()).overlay(RoundedRectangle(cornerRadius:22).stroke(DDLStyle.border,lineWidth:1))
    }
}
struct DDLStats:View {
    let state:DDLState
    var body:some View {
        let values:[(String,Int,Bool)]=[("已逾期",state.overdue,true),("7 天内",state.within(7),true),("30 天内",state.within(30),false),("高优先级",state.high,false)]
        HStack(spacing:0) {
            ForEach(values.indices,id:\.self) { i in
                let value=values[i]
                VStack(spacing:2) {
                    Text("\(value.1)").font(.system(size:20,weight:.semibold,design:.rounded)).monospacedDigit().foregroundStyle(value.2 && value.1>0 ? BoardStyle.urgentFG:Color.primary)
                    Text(value.0).font(.system(size:10)).foregroundStyle(.secondary)
                }.frame(maxWidth:.infinity)
                .accessibilityElement(children:.combine)
            }
        }.padding(.vertical,12)
        .background(Glass()).overlay(RoundedRectangle(cornerRadius:22).stroke(DDLStyle.border,lineWidth:1))
    }
}
struct DDLLegend:View {
    let projects:[DDLProject]
    var body:some View {
        LazyVGrid(columns:[GridItem(.flexible(),alignment:.leading),GridItem(.flexible(),alignment:.leading)],alignment:.leading,spacing:5) {
            ForEach(projects) { project in
                HStack(spacing:6) {Circle().fill(DDLStyle.color(project.id)).frame(width:7,height:7);Text(project.short).font(.system(size:10)).foregroundStyle(.secondary)}
            }
        }
    }
}
struct DDLLanes:View {
    let state:DDLState
    let open:(String)->Void
    var plotWidth:Double {min(16000,max(620,Double(state.axisStart.distance(to:state.axisEnd))*4.8))}
    var lanes:[DDLLane] {state.projects.map { p in DDLLane(tasks:state.tasks.filter{$0.projectID==p.id},start:state.axisStart,end:state.axisEnd,width:plotWidth)}}
    var chartHeight:Double {lanes.reduce(48){$0+$1.height}}
    func y(_ index:Int)->Double {28+lanes.prefix(index).reduce(0){$0+$1.height}+lanes[index].height/2}
    func x(_ day:DDLDay)->Double {8+Double(state.axisStart.distance(to:day))/Double(max(1,state.axisStart.distance(to:state.axisEnd)))*plotWidth}
    var body:some View {
        let lanes=self.lanes
        let plotWidth=self.plotWidth
        let chartHeight=lanes.reduce(48){$0+$1.height}
        let offsets=lanes.indices.map{ index in 28+lanes.prefix(index).reduce(0){$0+$1.height}+lanes[index].height/2 }
        let y:(Int)->Double = {offsets[$0]}
        let start=state.axisStart,end=state.axisEnd
        let x:(DDLDay)->Double = {8+Double(start.distance(to:$0))/Double(max(1,start.distance(to:end)))*plotWidth}
        HStack(alignment:.top,spacing:4) {
            VStack(spacing:0) {
                Color.clear.frame(height:28)
                ForEach(state.projects.indices,id:\.self) { i in
                    Text(state.projects[i].short).font(.system(size:10)).foregroundStyle(.secondary).frame(width:66,height:lanes[i].height,alignment:.leading)
                }
            }.frame(width:66,alignment:.leading).accessibilityHidden(true)
            ScrollView(.horizontal) {
                ZStack(alignment:.topLeading) {
                    Canvas { context,size in
                        for i in lanes.indices {
                            var path=Path();path.move(to:CGPoint(x:8,y:y(i)));path.addLine(to:CGPoint(x:plotWidth+8,y:y(i)))
                            context.stroke(path,with:.color(.primary.opacity(0.12)),lineWidth:1)
                        }
                        var d=state.axisStart
                        while d<=state.axisEnd {
                            if d.day==1 {
                                var p=Path();p.move(to:CGPoint(x:x(d),y:22));p.addLine(to:CGPoint(x:x(d),y:chartHeight-20))
                                context.stroke(p,with:.color(.primary.opacity(0.07)),lineWidth:1)
                                let label=(d.year != state.today.year ? "\(d.year)/":"")+"\(d.month)月"
                                context.draw(Text(label).font(.system(size:10)).foregroundColor(.secondary),at:CGPoint(x:x(d)+3,y:2),anchor:.topLeading)
                            }
                            d=d.adding(1)
                        }
                        context.draw(Text(state.axisStart.short).font(.system(size:10)).foregroundColor(.secondary),at:CGPoint(x:8,y:2),anchor:.topLeading)
                        context.draw(Text(state.axisEnd.iso).font(.system(size:10)).foregroundColor(.secondary),at:CGPoint(x:plotWidth+8,y:chartHeight-4),anchor:.bottomTrailing)
                        var today=Path();today.move(to:CGPoint(x:x(state.today),y:22));today.addLine(to:CGPoint(x:x(state.today),y:chartHeight-18))
                        context.stroke(today,with:.color(.red.opacity(0.85)),lineWidth:1.2)
                        context.draw(Text("今天").font(.system(size:10)).foregroundColor(.red),at:CGPoint(x:x(state.today)+3,y:chartHeight-4),anchor:.bottomLeading)
                    }.accessibilityHidden(true)
                    ForEach(state.projects.indices,id:\.self) { i in
                        ForEach(lanes[i].points) { point in
                            Button {open(point.task.id)} label: {
                                Circle().fill(point.task.pending ? DDLStyle.color(point.task.projectID).opacity(0.06):DDLStyle.color(point.task.projectID).opacity(0.9))
                                    .overlay(Circle().stroke(DDLStyle.color(point.task.projectID),lineWidth:point.task.pending ? 1.8:0))
                                    .frame(width:point.task.radius*2,height:point.task.radius*2).frame(width:17,height:17)
                            }.buttonStyle(.plain).help(point.task.tooltip)
                            .accessibilityLabel(point.task.tooltip)
                            .position(x:8+point.x,y:y(i)+point.verticalOffset)
                        }
                    }
                }.frame(width:plotWidth+16,height:chartHeight)
            }.frame(height:chartHeight+10)
        }
    }
}
struct DDLWeeklyBars:View {
    let state:DDLState
    var weeks:[DDLWeek] {state.chartWeeks}
    var width:Double {max(300,Double(weeks.count)*35+38)}
    var scale:Double {let v=weeks.map{$0.totalMinutes/60}.max() ?? 0;let step=v>16 ? 8.0:4.0;return max(4,ceil(v/step)*step)}
    let top:Double=18
    let baseline:Double=160
    var strideWidth:Double {(width-38)/Double(max(1,weeks.count))}
    var body:some View {
        let weeks=self.weeks
        let width=self.width
        let scale=self.scale
        let strideWidth=(width-38)/Double(max(1,weeks.count))
        ScrollView(.horizontal) {
            ZStack(alignment:.topLeading) {
                Canvas { context,size in
                    let step=scale>16 ? 8.0:4.0
                    for v in stride(from:0.0,through:scale,by:step) {
                        let y=baseline-v/scale*(baseline-top)
                        var p=Path();p.move(to:CGPoint(x:28,y:y));p.addLine(to:CGPoint(x:width,y:y))
                        context.stroke(p,with:.color(.primary.opacity(0.08)),lineWidth:1)
                        context.draw(Text(DDLState.number(v)+"h").font(.system(size:10)).foregroundColor(.secondary),at:CGPoint(x:24,y:y),anchor:.trailing)
                    }
                    for i in weeks.indices {
                        let x=30+(Double(i)+0.5)*strideWidth
                        if i%2==0 || weeks.count<=8 {context.draw(Text(weeks[i].start.short).font(.system(size:10)).foregroundColor(.secondary),at:CGPoint(x:x,y:178))}
                        let hours=weeks[i].totalMinutes/60
                        if hours>=max(6,scale*0.6) {context.draw(Text(DDLState.number(hours)+"h").font(.system(size:10)).foregroundColor(.primary),at:CGPoint(x:x,y:baseline-hours/scale*(baseline-top)-8))}
                    }
                }.accessibilityHidden(true)
                ForEach(weeks.indices,id:\.self) { i in
                    ForEach(state.projects.indices,id:\.self) { j in
                        let project=state.projects[j]
                        let hours=weeks[i].hours(project.id)
                        let before=state.projects.prefix(j).reduce(0.0){$0+weeks[i].hours($1.id)}
                        if hours>0 {
                            Rectangle().fill(DDLStyle.color(project.id).opacity(0.9))
                                .frame(width:strideWidth*0.68,height:hours/scale*(baseline-top))
                                .position(x:30+(Double(i)+0.5)*strideWidth,y:baseline-(before+hours/2)/scale*(baseline-top))
                                .help("\(weeks[i].start.iso) 周 · \(project.short) · \(DDLState.number(hours))小时")
                                .accessibilityLabel("\(weeks[i].start.iso) 周 · \(project.short) · \(DDLState.number(hours))小时")
                        }
                    }
                }
            }.frame(width:width,height:195)
        }.frame(height:205)
    }
}
struct DDLTaskRow:View {
    let task:DDLTask
    let today:DDLDay
    let open:(String)->Void
    var body:some View {
        let due=task.due!
        let left=today.distance(to:due)
        let tags=TitleFormatter.format(task.name).tags
        let label=left<0 ? "逾期\(-left)天":(left==0 ? "今天":"\(left)天")
        let urgent=left<=5,soon=left<=7
        return Button {open(task.id)} label: {
            HStack(alignment:.top,spacing:10) {
                VStack(alignment:.leading,spacing:2) {
                    Text(due.short).font(.system(size:10,weight:.medium,design:.monospaced))
                    Text(due.weekday).font(.system(size:10)).foregroundStyle(.secondary)
                }.frame(width:43,alignment:.leading)
                VStack(alignment:.leading,spacing:5) {
                    HStack(spacing:6) {
                        Text(DDLProject.names[task.projectID] ?? task.projectID).font(.system(size:10)).foregroundStyle(BoardStyle.ink(task.projectID)).padding(.horizontal,6).padding(.vertical,2)
                            .overlay(Capsule().stroke(BoardStyle.dot(task.projectID).opacity(0.5),lineWidth:0.7))
                        Text(task.id).font(.system(size:10,design:.monospaced)).foregroundStyle(.secondary)
                        Spacer(minLength:0)
                        Text(label).font(.system(size:10,weight:.semibold)).monospacedDigit().fixedSize()
                            .padding(.horizontal,5).padding(.vertical,1)
                            .background(Capsule().fill(urgent ? BoardStyle.urgentBG:(soon ? BoardStyle.soonBG:BoardStyle.neutralBG)))
                            .foregroundStyle(urgent ? BoardStyle.urgentFG:(soon ? BoardStyle.soonFG:Color.secondary))
                    }
                    Text(task.name).font(.system(size:12,weight:.medium)).foregroundStyle(.primary).fixedSize(horizontal:false,vertical:true).multilineTextAlignment(.leading)
                    HStack(spacing:7) {
                        Text(task.priority.isEmpty ? "未设优先级":task.priority+"优先级").foregroundStyle(task.priority=="高" ? BoardStyle.urgentFG:Color.secondary)
                        if task.pending {TagChip(text:"待确认")}
                        ForEach(tags,id:\.self) {TagChip(text:$0)}
                        Spacer(minLength:0)
                        Text(task.duration).monospacedDigit()
                    }.font(.system(size:10)).foregroundStyle(.secondary)
                }
            }.padding(.vertical,7).frame(maxWidth:.infinity,alignment:.leading).contentShape(Rectangle())
        }.buttonStyle(.plain).help(task.tooltip).accessibilityLabel(task.tooltip+" · "+task.duration+" · 查看任务详情")
    }
}
struct DDLTimeline:View {
    @ObservedObject var model:Model
    let back:()->Void
    let open:(String)->Void
    var state:DDLState {DDLState(tables:model.data?.tables ?? [:])}
    var body:some View {
        let current=state
        ScrollView(.vertical) {
            VStack(alignment:.leading,spacing:10) {
                DDLHeader(title:"DDL 时间线",backTitle:"返回看板",back:back)
                DDLStats(state:current)
                DDLGlassCard("截止分布",note:"圆点大小表示优先级；空心表示待确认。可横向滚动，悬停查看任务。") {
                    DDLLegend(projects:current.projects)
                    DDLLanes(state:current,open:open)
                    if !current.earlierTasks.isEmpty {Text("本周前已逾期 \(current.earlierTasks.count) 项，见按周清单。日期轴从本周一开始。").font(.system(size:10)).foregroundStyle(BoardStyle.urgentFG)}
                }
                DDLGlassCard("每周到期工作量",note:"按截止日所在周汇总预计小时，按项目堆叠。未估时任务不计入柱高。") {
                    DDLWeeklyBars(state:current)
                }
                DDLGlassCard("按周清单",note:"7 天内包含今天至第 6 天；30 天内包含今天至第 29 天。") {
                    if current.tasks.isEmpty {Text("暂无未完成且有截止日期的任务").font(.system(size:12)).foregroundStyle(.secondary)}
                    ForEach(current.weeks) { week in
                        VStack(alignment:.leading,spacing:6) {
                            HStack(alignment:.firstTextBaseline) {
                                VStack(alignment:.leading,spacing:2) {
                                    Text(week.start.weekLabel(relativeTo:current.today)).font(.system(size:12,weight:.semibold))
                                    Text(week.start.short+"–"+week.start.adding(6).short).font(.system(size:10)).foregroundStyle(.secondary)
                                }
                                Spacer(minLength:4)
                                VStack(alignment:.trailing,spacing:2) {
                                    Text(DDLState.number(week.totalMinutes/60)+"小时").font(.system(size:10)).monospacedDigit()
                                    if week.unestimated>0 {Text("\(week.unestimated)项未估时").font(.system(size:10)).foregroundStyle(.secondary)}
                                }
                            }.padding(.top,6)
                            ForEach(week.tasks) { task in
                                DDLTaskRow(task:task,today:current.today,open:open)
                                if task.id != week.tasks.last?.id {Divider().opacity(0.35)}
                            }
                        }
                        if week.id != current.weeks.last?.id {Divider().padding(.vertical,5)}
                    }
                }
                if current.invalidDates>0 {Text("\(current.invalidDates)项截止日期格式无效，未计入；源数据保持不变。").font(.system(size:10)).foregroundStyle(.orange)}
                Text("数据更新 "+(model.data?.syncedAt ?? "—")).font(.system(size:10)).foregroundStyle(.secondary).padding(.horizontal,8)
                if let error=model.error {Text(error).font(.system(size:10)).foregroundStyle(.orange)}
            }.padding(8)
        }
    }
}
struct DDLTaskDetail:View {
    @ObservedObject var model:Model
    let id:String
    let back:()->Void
    var backTitle:String="返回时间线"
    var task:DDLTask? {model.rows("Tasks").first{cell($0,0)==id}.map(DDLTask.init)}
    var body:some View {
        ScrollView {
            VStack(alignment:.leading,spacing:10) {
                DDLHeader(title:"任务详情",backTitle:backTitle,back:back)
                if let task=task {
                    DDLGlassCard(task.id) {
                        Text(task.name).font(.system(size:14,weight:.semibold)).fixedSize(horizontal:false,vertical:true)
                        Divider().padding(.vertical,3)
                        field("项目",(DDLProject.names[task.projectID] ?? task.projectID)+" · "+task.projectID)
                        field("状态",task.status)
                        field("优先级",task.priority)
                        field("截止日期",task.rawDue.isEmpty ? "未填写":task.rawDue+(task.due.map{" · "+$0.weekday} ?? " · 日期格式无效"))
                        field("预计时长",task.duration)
                    }
                    DDLGlassCard("来源 / 说明") {
                        Text(task.source.isEmpty ? "未填写":task.source).font(.system(size:12)).fixedSize(horizontal:false,vertical:true).textSelection(.enabled)
                    }
                } else {DDLGlassCard("") {Text("此任务已不在当前快照中。").font(.system(size:12)).foregroundStyle(.secondary)}}
            }.padding(8)
        }
    }
    func field(_ label:String,_ value:String)->some View {
        HStack(alignment:.top,spacing:12) {Text(label).foregroundStyle(.secondary).frame(width:60,alignment:.leading);Text(value.isEmpty ? "未填写":value).frame(maxWidth:.infinity,alignment:.leading).textSelection(.enabled)}.font(.system(size:12)).padding(.vertical,3)
    }
}
// 任务池页：未完成、未取消、且没有排进任何日计划的任务，按优先级分组
struct PoolPage:View {
    @ObservedObject var model:Model
    let back:()->Void
    let open:(String)->Void
    var body:some View {
        let tasks=sortedBacklog(model.rows("Tasks"),plans:model.rows("Daily Plan")).map(DDLTask.init)
        let today=DDLDay.londonToday()
        let groups:[(String,[DDLTask])]=[("高","高优先级"),("中","中优先级"),("低","低优先级"),("","未设优先级")].map { key,name in
            (name,tasks.filter{key.isEmpty ? !["高","中","低"].contains($0.priority):$0.priority==key})
        }.filter{!$0.1.isEmpty}
        let values:[(String,Int,Bool)]=[("未排期",tasks.count,false),("高优先级",tasks.filter{$0.priority=="高"}.count,true),("有截止日",tasks.filter{$0.due != nil}.count,false),("待确认",tasks.filter{$0.pending}.count,false)]
        return ScrollView(.vertical) {
            VStack(alignment:.leading,spacing:10) {
                DDLHeader(title:"任务池",backTitle:"返回看板",back:back)
                HStack(spacing:0) {
                    ForEach(values.indices,id:\.self) { i in
                        VStack(spacing:2) {
                            Text("\(values[i].1)").font(.system(size:20,weight:.semibold,design:.rounded)).monospacedDigit().foregroundStyle(values[i].2 && values[i].1>0 ? BoardStyle.urgentFG:Color.primary)
                            Text(values[i].0).font(.system(size:10)).foregroundStyle(.secondary)
                        }.frame(maxWidth:.infinity).accessibilityElement(children:.combine)
                    }
                }.padding(.vertical,12)
                .background(Glass()).overlay(RoundedRectangle(cornerRadius:22).stroke(DDLStyle.border,lineWidth:1))
                if tasks.isEmpty {DDLGlassCard("") {Text("没有未排期任务").font(.system(size:12)).foregroundStyle(.secondary)}}
                ForEach(groups.indices,id:\.self) { gi in
                    DDLGlassCard(groups[gi].0+" · \(groups[gi].1.count) 项") {
                        VStack(alignment:.leading,spacing:0) {
                            ForEach(groups[gi].1) { task in
                                PoolRow(task:task,today:today,open:open)
                                if task.id != groups[gi].1.last?.id {Divider().opacity(0.35)}
                            }
                        }
                    }
                }
                Text("任务池 = 未完成、未取消、且没有排进任何日计划的任务；同组内按截止日期排序。点任务查看详情。").font(.system(size:10)).foregroundStyle(.secondary).padding(.horizontal,8)
                Text("数据更新 "+(model.data?.syncedAt ?? "—")).font(.system(size:10)).foregroundStyle(.secondary).padding(.horizontal,8)
            }.padding(8)
        }
    }
}
struct PoolRow:View {
    let task:DDLTask
    let today:DDLDay
    let open:(String)->Void
    var body:some View {
        let tags=TitleFormatter.format(task.name).tags
        return Button {open(task.id)} label: {
            VStack(alignment:.leading,spacing:4) {
                HStack(spacing:6) {
                    Text(DDLProject.names[task.projectID] ?? task.projectID).font(.system(size:10)).foregroundStyle(BoardStyle.ink(task.projectID)).padding(.horizontal,6).padding(.vertical,2)
                        .overlay(Capsule().stroke(BoardStyle.dot(task.projectID).opacity(0.5),lineWidth:0.7))
                    Text(task.id).font(.system(size:10,design:.monospaced)).foregroundStyle(.secondary)
                    if task.pending {TagChip(text:"待确认")}
                    ForEach(tags,id:\.self) {TagChip(text:$0)}
                    Spacer(minLength:0)
                    if let due=task.due {DueBadge(due:due,today:today)}
                }
                Text(task.name).font(.system(size:12,weight:.medium)).foregroundStyle(.primary).fixedSize(horizontal:false,vertical:true).multilineTextAlignment(.leading)
                HStack(spacing:7) {
                    Text(task.status)
                    Spacer(minLength:0)
                    Text(task.duration).monospacedDigit()
                }.font(.system(size:10)).foregroundStyle(.secondary)
            }.padding(.vertical,7).frame(maxWidth:.infinity,alignment:.leading).contentShape(Rectangle())
        }.buttonStyle(.plain).help(task.tooltip).accessibilityLabel(task.tooltip+" · 查看任务详情")
    }
}
struct DueBadge:View {
    let due:DDLDay
    let today:DDLDay
    var body:some View {
        let left=today.distance(to:due)
        let label=left<0 ? "逾期\(-left)天":(left==0 ? "今天":"\(left)天")
        let urgent=left<=5,soon=left<=7
        return HStack(spacing:4) {
            Text(String(format:"%02d/%02d",due.month,due.day)+" "+due.weekday).font(.system(size:10)).monospacedDigit().foregroundStyle(.secondary)
            Text(label).font(.system(size:10,weight:.semibold)).monospacedDigit().fixedSize()
                .padding(.horizontal,5).padding(.vertical,1)
                .background(Capsule().fill(urgent ? BoardStyle.urgentBG:(soon ? BoardStyle.soonBG:BoardStyle.neutralBG)))
                .foregroundStyle(urgent ? BoardStyle.urgentFG:(soon ? BoardStyle.soonFG:Color.secondary))
        }
    }
}
enum DesktopPage:Equatable {case board,timeline,task(String),pool,poolTask(String)}
struct DesktopRoot:View {
    @ObservedObject var model:Model
    @State var page:DesktopPage = .board
    var body:some View {
        Group {
            switch page {
            case .board:Board(model:model,showTimeline:{page = .timeline},showPool:{page = .pool})
            case .pool:PoolPage(model:model,back:{page = .board},open:{page = .poolTask($0)})
            case .poolTask(let id):DDLTaskDetail(model:model,id:id,back:{page = .pool},backTitle:"返回任务池")
            case .timeline:DDLTimeline(model:model,back:{page = .board},open:{page = .task($0)})
            case .task(let id):DDLTaskDetail(model:model,id:id,back:{page = .timeline})
            }
        }.frame(width:model.layoutSize.width,height:model.layoutSize.height)
        .onReceive(NotificationCenter.default.publisher(for:Notification.Name("PersonalWorkspace.OpenTimeline"))) { _ in page = .timeline }
        .onChange(of:page) { next in
            switch next {case .board:model.activePage="board";case .timeline:model.activePage="timeline";case .task(let id):model.activePage="task:"+id;case .pool:model.activePage="pool";case .poolTask(let id):model.activePage="pool-task:"+id}
            model.writeDiagnostics()
        }
    }
}
