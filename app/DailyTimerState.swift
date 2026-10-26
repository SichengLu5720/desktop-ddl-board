import Foundation

// A work day begins at 07:00 London time, including across DST changes.
enum WorkDayClock {
    static var calendar:Calendar {var c=Calendar(identifier:.gregorian);c.timeZone=TimeZone(identifier:"Europe/London")!;return c}
    static func start(at now:Date)->Date {
        let c=calendar
        let seven=c.date(bySettingHour:7,minute:0,second:0,of:now)!
        return now>=seven ? seven:c.date(byAdding:.day,value:-1,to:seven)!
    }
    static func key(at now:Date)->String {
        let parts=calendar.dateComponents([.year,.month,.day],from:start(at:now))
        return String(format:"%04d-%02d-%02d",parts.year!,parts.month!,parts.day!)
    }
    static func nextReset(after now:Date)->Date {calendar.date(byAdding:.day,value:1,to:start(at:now))!}
}

struct DailyTimerState:Codable,Equatable {
    var version=1
    var workDay:String
    var accumulated:TimeInterval=0
    var startedAt:Date?
    init(at now:Date) {workDay=WorkDayClock.key(at:now)}
    var running:Bool {startedAt != nil}
    func elapsed(at now:Date)->TimeInterval {
        guard workDay==WorkDayClock.key(at:now) else {return 0}
        return accumulated+max(0,startedAt.map{now.timeIntervalSince($0)} ?? 0)
    }
    mutating func reconcile(at now:Date)->Bool {
        guard workDay != WorkDayClock.key(at:now) else {return false}
        self=DailyTimerState(at:now);return true
    }
    mutating func toggle(at now:Date) {
        _=reconcile(at:now)
        if running {accumulated=elapsed(at:now);startedAt=nil} else {startedAt=now}
    }
    func valid(at now:Date)->Bool {
        version==1 && accumulated.isFinite && accumulated>=0 && accumulated<=25*3600 &&
        (startedAt.map{WorkDayClock.key(at:$0)==workDay} ?? true)
    }
    static func display(_ seconds:TimeInterval)->String {
        let hundredths=Int((max(0,min(seconds,26*3600))*100).rounded(.down))
        let n=hundredths/100
        return String(format:"%02d:%02d:%02d.%02d",n/3600,(n%3600)/60,n%60,hundredths%100)
    }
}

enum DailyTimerCodec {
    static func decode(_ data:Data)throws->DailyTimerState {
        let decoder=JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let value=try decoder.singleValueContainer().decode(String.self)
            let fraction=ISO8601DateFormatter();fraction.formatOptions=[.withInternetDateTime,.withFractionalSeconds]
            if let date=fraction.date(from:value) ?? ISO8601DateFormatter().date(from:value) {return date}
            throw DecodingError.dataCorrupted(.init(codingPath:decoder.codingPath,debugDescription:"Invalid timer timestamp"))
        }
        return try decoder.decode(DailyTimerState.self,from:data)
    }
    static func encode(_ state:DailyTimerState)throws->Data {
        let encoder=JSONEncoder();encoder.outputFormatting=[.sortedKeys]
        encoder.dateEncodingStrategy = .custom { date,encoder in
            let formatter=ISO8601DateFormatter();formatter.formatOptions=[.withInternetDateTime,.withFractionalSeconds]
            var value=encoder.singleValueContainer();try value.encode(formatter.string(from:date))
        }
        return try encoder.encode(state)
    }
}
