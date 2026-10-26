import Foundation

// Date-only arithmetic in UTC; "today" is obtained in Europe/London.
// This keeps seven calendar days stable across daylight-saving changes.
struct DDLDay: Hashable, Comparable {
    let iso: String
    let date: Date
    static var calendar: Calendar { var c=Calendar(identifier:.gregorian);c.timeZone=TimeZone(secondsFromGMT:0)!;c.firstWeekday=2;return c }
    init?(_ value:String) {
        guard value.count==10 else{return nil}
        let parts=value.split(separator:"-",omittingEmptySubsequences:false)
        guard parts.count==3,parts[0].count==4,parts[1].count==2,parts[2].count==2,
              let year=Int(parts[0]),let month=Int(parts[1]),let day=Int(parts[2]),year>0,
              let d=Self.calendar.date(from:DateComponents(year:year,month:month,day:day)) else{return nil}
        let check=Self.calendar.dateComponents([.year,.month,.day],from:d)
        guard check.year==year,check.month==month,check.day==day else{return nil}
        iso=value;date=d
    }
    private init(date:Date) {
        let parts=Self.calendar.dateComponents([.year,.month,.day],from:date)
        iso=String(format:"%04d-%02d-%02d",parts.year!,parts.month!,parts.day!);self.date=date
    }
    static func <(a:Self,b:Self)->Bool {a.iso<b.iso}
    static func londonToday(_ now:Date=Date())->Self {
        let f=DateFormatter();f.calendar=Self.calendar;f.locale=Locale(identifier:"en_US_POSIX");f.timeZone=TimeZone(identifier:"Europe/London");f.dateFormat="yyyy-MM-dd"
        return Self(f.string(from:now))!
    }
    func adding(_ days:Int)->Self {
        let d=Self.calendar.date(byAdding:.day,value:days,to:date)!
        return Self(date:d)
    }
    func distance(to other:Self)->Int {Self.calendar.dateComponents([.day],from:date,to:other.date).day!}
    var monday:Self {adding(-((Self.calendar.component(.weekday,from:date)+5)%7))}
    var short:String {"\(Self.calendar.component(.month,from:date))/\(Self.calendar.component(.day,from:date))"}
    var weekday:String {"周"+["日","一","二","三","四","五","六"][Self.calendar.component(.weekday,from:date)-1]}
    var month:Int {Self.calendar.component(.month,from:date)}
    var day:Int {Self.calendar.component(.day,from:date)}
    var year:Int {Self.calendar.component(.year,from:date)}
    func weekLabel(relativeTo today:Self)->String {
        if self==today.monday {return "本周"}
        if self==today.monday.adding(7) {return "下周"}
        let prefix=year==today.year ? "":"\(year)年"
        return (self<today.monday ? "已逾期 · ":"")+prefix+"\(month)月第\((day+6)/7)周"
    }
}

struct DDLTask:Identifiable,Equatable {
    let id:String
    let projectID:String
    let name:String
    let status:String
    let priority:String
    let minutes:Double?
    let rawMinutes:String
    let rawDue:String
    let due:DDLDay?
    let source:String
    init(_ row:[String]) {
        func value(_ i:Int)->String {i<row.count ? row[i].trimmingCharacters(in:.whitespacesAndNewlines):""}
        id=value(0);projectID=value(1);name=value(2);status=value(3);priority=value(4);rawMinutes=value(5);rawDue=value(6);source=value(7)
        if let n=Double(rawMinutes),n.isFinite,n>=0 {minutes=n}else{minutes=nil}
        due=DDLDay(rawDue)
    }
    var pending:Bool {status=="待确认"}
    var active:Bool {!["已完成","取消"].contains(status)}
    var rank:Int {["高":0,"中":1,"低":2][priority] ?? 3}
    var radius:Double {["高":6.5,"中":5.0,"低":3.5][priority] ?? 3.5}
    var duration:String {
        guard let n=minutes else{return "未估时"}
        if n<60 {return DDLState.number(n)+"分钟"}
        return DDLState.number(n/60)+"小时"
    }
    var tooltip:String {"\(id) · \(name)\n\(rawDue) · \(priority.isEmpty ? "未设优先级":priority)\(pending ? " · 待确认":"")"}
}

struct DDLProject:Identifiable {
    let id:String
    let name:String
    let short:String
    static let names=["P01":"硕士申请","P02":"课程与论文","P03":"求职与实习","P04":"AI 作品集"]
}
struct DDLWeek:Identifiable {
    let start:DDLDay
    let tasks:[DDLTask]
    var id:String {start.iso}
    var totalMinutes:Double {tasks.compactMap(\.minutes).reduce(0,+)}
    var unestimated:Int {tasks.filter{$0.minutes==nil}.count}
    func hours(_ project:String)->Double {tasks.filter{$0.projectID==project}.compactMap(\.minutes).reduce(0,+)/60}
}
struct DDLState {
    let today:DDLDay
    let allTasks:[DDLTask]
    let tasks:[DDLTask]
    let projects:[DDLProject]
    let invalidDates:Int
    init(tables:[String:[[String]]],today:DDLDay = .londonToday()) {
        self.today=today
        allTasks=Array((tables["Tasks"] ?? []).dropFirst()).map(DDLTask.init)
        tasks=allTasks.filter{$0.active && $0.due != nil}.sorted {
            if $0.due != $1.due {return $0.due! < $1.due!}
            if $0.rank != $1.rank {return $0.rank < $1.rank}
            return $0.id < $1.id
        }
        invalidDates=allTasks.filter{$0.active && !$0.rawDue.isEmpty && $0.due==nil}.count
        let rows=Array((tables["Projects"] ?? []).dropFirst())
        projects=["P01","P02","P03","P04"].map { id in
            let name=rows.first{$0.first==id}.flatMap{$0.count>1 ? $0[1]:nil} ?? DDLProject.names[id]!
            return DDLProject(id:id,name:name,short:DDLProject.names[id]!)
        }
    }
    static func number(_ n:Double)->String {n.rounded()==n ? String(format:"%.0f",n):String(format:"%.1f",n)}
    var overdue:Int {tasks.filter{$0.due!<today}.count}
    func within(_ days:Int)->Int {tasks.filter{$0.due!>=today && $0.due!<today.adding(days)}.count}
    var high:Int {tasks.filter{$0.priority=="高"}.count}
    var axisStart:DDLDay {today.monday}
    var axisEnd:DDLDay {max(tasks.last?.due ?? today,today.monday.adding(6))}
    var earlierTasks:[DDLTask] {tasks.filter{$0.due!<axisStart}}
    var weeks:[DDLWeek] {
        let groups=Dictionary(grouping:tasks,by:{$0.due!.monday})
        return groups.keys.sorted().map{DDLWeek(start:$0,tasks:groups[$0]!)}
    }
    var chartWeeks:[DDLWeek] {
        let groups=Dictionary(grouping:tasks,by:{$0.due!.monday})
        var day=min(today.monday,weeks.first?.start ?? today.monday)
        let end=max(today.monday,weeks.last?.start ?? today.monday)
        var result:[DDLWeek]=[]
        while day<=end {result.append(DDLWeek(start:day,tasks:groups[day] ?? []));day=day.adding(7)}
        return result
    }
}

struct DDLPlotPoint:Identifiable {
    let task:DDLTask
    let x:Double
    let slot:Int
    var id:String {task.id}
    var verticalOffset:Double {slot==0 ? 0:Double((slot+1)/2)*(slot%2==1 ? -20:20)}
}
struct DDLLane {
    let points:[DDLPlotPoint]
    let height:Double
    init(tasks:[DDLTask],start:DDLDay,end:DDLDay,width:Double) {
        var points:[DDLPlotPoint]=[];var ends:[Double]=[]
        let span=Double(max(1,start.distance(to:end)))
        for task in tasks.filter({$0.due!>=start && $0.due!<=end}) {
            let x=Double(start.distance(to:task.due!))/span*width
            let slot=ends.firstIndex(where:{$0<x-task.radius-5}) ?? ends.count
            if slot==ends.count {ends.append(x+task.radius)}else{ends[slot]=x+task.radius}
            points.append(DDLPlotPoint(task:task,x:x,slot:slot))
        }
        self.points=points
        height=max(54,Double(ends.count/2)*40+24)
    }
}
