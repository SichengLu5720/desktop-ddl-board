import Foundation

var checks=0
func expect(_ value:Bool,_ message:String) {if !value {fputs("FAIL: \(message)\n",stderr);exit(1)};checks+=1}
let today=DDLDay("2026-10-24")!
func row(_ id:String,_ date:String,_ status:String="待开始",_ priority:String="高",_ minutes:String="60",_ project:String="P01")->[String] {[id,project,"Task "+id,status,priority,minutes,date,"Evidence"]}
func state(_ rows:[[String]])->DDLState {DDLState(tables:["Tasks":[["Task ID","Project ID","任务","状态","优先级","预计分钟","截止日期","来源 / 说明"]]+rows],today:today)}
let s=state([row("old","2026-10-18"),row("yesterday","2026-10-23"),row("today","2026-10-24"),row("dst","2026-10-25"),row("last7","2026-10-30"),row("day7","2026-10-31"),row("last30","2026-11-22"),row("day30","2026-11-23"),row("done","2026-10-24","已完成"),row("cancelled","2026-10-24","取消"),row("empty",""),row("bad","2026-02-30"),row("spaces","2026-11-02"," 待确认 ","中","90","P02")])
expect(s.tasks.count==9,"Only active valid dated tasks")
expect(s.invalidDates==1,"Invalid dates are explicit and excluded")
expect(s.overdue==2,"Overdue strictly before today")
expect(s.within(7)==3,"7-day window includes today through day6, excluding overdue/day7")
expect(s.within(30)==6,"30-day window includes day29, excluding day30")
expect(s.high==8,"High count shares the same active dated filter")
expect(s.tasks.first{$0.id=="spaces"}!.pending,"Pending status trims whitespace")
expect(s.axisStart.iso=="2026-10-19","Axis starts this Monday")
expect(s.axisEnd.iso=="2026-11-23","Axis ends at last deadline")
expect(s.earlierTasks.map(\.id)==["old"],"Earlier overdue not plotted at a false date")
expect(DDLDay("2026-10-25")!.adding(1).iso=="2026-10-26","DST calendar day arithmetic")
expect(today.adding(7).iso=="2026-10-31","Seven days across DST")
expect(DDLDay("2027-01-01")!.monday.iso=="2026-12-28","Week crosses year correctly")
expect(today.monday.weekLabel(relativeTo:today)=="本周","This week label")
expect(today.monday.adding(7).weekLabel(relativeTo:today)=="下周","Next week label")
expect(DDLDay("2026-11-02")!.weekLabel(relativeTo:today)=="11月第1周","Later month/week label")
expect(DDLDay("2027-01-04")!.weekLabel(relativeTo:today)=="2027年1月第1周","Cross-year label unambiguous")
let workload=state([row("p1","2026-10-26","待开始","高","90"),row("p2","2026-10-27","待确认","中","30","P02"),row("unknown","2026-10-28","待开始","低",""),row("zero","2026-10-29","待开始","低","0"),row("negative","2026-10-30","待开始","低","-40")])
expect(workload.weeks.count==1,"Weekly grouping")
let w=workload.weeks[0]
expect(w.totalMinutes==120 && w.hours("P01")==1.5 && w.hours("P02")==0.5,"Stacked hours sum matches minutes by project")
expect(w.unestimated==2,"Unknown and invalid estimates never invented")
expect(workload.allTasks.first{$0.id=="zero"}!.duration=="0分钟","Zero is distinct from missing duration")
let empty=state([])
expect(empty.tasks.isEmpty && empty.chartWeeks.count==1 && empty.within(7)==0 && empty.high==0,"Empty data is safe")
let past=state([row("past","2026-09-01")])
expect(past.axisEnd==today.monday.adding(6),"All-overdue plot keeps safe current-week axis")
let points=(0..<20).map{DDLTask(row("S\($0)","2026-10-26"))}
let lane=DDLLane(tasks:points,start:today.monday,end:today.adding(20),width:800)
expect(Set(lane.points.map(\.verticalOffset)).count==20,"Same-day points all have distinct vertical positions")
expect(lane.points.allSatisfy{abs($0.verticalOffset)+$0.task.radius<lane.height/2},"Point stacks fit within their project lane")
let close=DDLLane(tasks:[DDLTask(row("C1","2026-10-26")),DDLTask(row("C2","2026-10-27"))],start:today.monday,end:today.adding(180),width:620)
expect(close.points[0].slot != close.points[1].slot,"Nearby dates with overlapping circles also separate")
expect(DDLDay("2026-13-01")==nil && DDLDay("2026-02-30")==nil && DDLDay("2026-1-1")==nil,"Strict ISO dates")
expect(workload.allTasks.first{$0.id=="p1"}!.radius>workload.allTasks.first{$0.id=="p2"}!.radius,"Priority sizes")
print("PASS: \(checks) deadline/filter/calendar/workload/collision checks")

if CommandLine.arguments.count==2 {
    let bytes=try Data(contentsOf:URL(fileURLWithPath:CommandLine.arguments[1]))
    let root=try JSONSerialization.jsonObject(with:bytes) as! [String:Any]
    let current=DDLState(tables:root["tables"] as! [String:[[String]]])
    let info:[String:Any]=["today":current.today.iso,"tasks":current.tasks.count,"overdue":current.overdue,"within7":current.within(7),"within30":current.within(30),"high":current.high,"invalidDates":current.invalidDates,"weeks":current.weeks.count,"totalHours":current.tasks.compactMap(\.minutes).reduce(0,+)/60]
    print(String(data:try JSONSerialization.data(withJSONObject:info,options:[.sortedKeys]),encoding:.utf8)!)
}
