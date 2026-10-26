import Foundation

let f=ISO8601DateFormatter()
func date(_ s:String)->Date {f.date(from:s)!}
var checks=0
func expect(_ condition:Bool,_ message:String) {guard condition else {fatalError(message)};checks+=1}
let before=date("2026-10-24T05:59:59Z") // 06:59:59 BST
let seven=date("2026-10-24T06:00:00Z")
expect(WorkDayClock.key(at:before)=="2026-10-23","Before seven belongs to previous workday")
expect(WorkDayClock.key(at:seven)=="2026-10-24","Exactly seven begins new workday")
expect(WorkDayClock.nextReset(after:before)==seven,"Next reset targets local seven")
expect(WorkDayClock.nextReset(after:seven)==date("2026-10-25T07:00:00Z"),"Fall DST reset uses London clock")
expect(WorkDayClock.nextReset(after:seven).timeIntervalSince(seven)==25*3600,"Fall workday is 25 hours")
let spring=date("2027-03-27T07:00:00Z")
expect(WorkDayClock.nextReset(after:spring)==date("2027-03-28T06:00:00Z"),"Spring DST reset uses London clock")
expect(WorkDayClock.nextReset(after:spring).timeIntervalSince(spring)==23*3600,"Spring workday is 23 hours")
var s=DailyTimerState(at:seven)
expect(!s.running && s.elapsed(at:seven)==0,"New timer paused and zero")
s.toggle(at:seven)
expect(s.running && s.elapsed(at:seven.addingTimeInterval(65))==65,"Start measures elapsed time")
s.toggle(at:seven.addingTimeInterval(65))
expect(!s.running && s.elapsed(at:seven.addingTimeInterval(300))==65,"Pause stops accumulating")
s.toggle(at:seven.addingTimeInterval(300))
expect(s.elapsed(at:seven.addingTimeInterval(310))==75,"Resume adds to prior total")
let encoder=JSONEncoder();encoder.dateEncodingStrategy = .iso8601
let decoder=JSONDecoder();decoder.dateDecodingStrategy = .iso8601
let restored=try decoder.decode(DailyTimerState.self,from:encoder.encode(s))
expect(restored==s && restored.elapsed(at:seven.addingTimeInterval(3600))==3365,"Restart restores persisted anchor and elapsed duration")
expect(restored.elapsed(at:WorkDayClock.nextReset(after:seven))==0,"Display cannot leak prior workday at reset")
var next=restored
expect(next.reconcile(at:WorkDayClock.nextReset(after:seven)) && !next.running && next.accumulated==0,"Scheduled reset zeroes and pauses")
expect(!next.reconcile(at:WorkDayClock.nextReset(after:seven)),"Repeated wake/reset is idempotent")
var slept=restored
expect(slept.reconcile(at:seven.addingTimeInterval(4*86400)) && !slept.running,"Wake or relaunch several days later starts paused")
expect(DailyTimerState.display(3661)=="01:01:01.00","Hours minutes seconds and hundredths format")
expect(DailyTimerState.display(3661.456)=="01:01:01.45","Hundredths truncate without rounding up")
expect(DailyTimerState.display(59.999)=="00:00:59.99" && DailyTimerState.display(60)=="00:01:00.00","Hundredths roll over correctly")
var fractional=DailyTimerState(at:seven);fractional.toggle(at:seven.addingTimeInterval(0.457))
let exact=try DailyTimerCodec.decode(DailyTimerCodec.encode(fractional))
expect(abs(exact.startedAt!.timeIntervalSince(fractional.startedAt!))<0.002,"Restart retains subsecond anchor")
expect(try DailyTimerCodec.decode(encoder.encode(s))==s,"Existing whole-second timer records migrate")
var corrupt=s;corrupt.accumulated = .infinity
expect(!corrupt.valid(at:seven),"Reject non-finite persisted durations")
print("PASS: \(checks) timer, restart, reset, wake and DST checks")
