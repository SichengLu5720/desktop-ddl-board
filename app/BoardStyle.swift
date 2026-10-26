import SwiftUI
import AppKit

// 浅色 / 深色自动切换的看板配色。点状和条形用系统色（随外观变化），文字用对比度足够的深 / 浅变体。
enum BoardStyle {
    static func hex(_ v:UInt32,_ alpha:CGFloat=1)->NSColor {
        NSColor(srgbRed:CGFloat((v>>16)&0xFF)/255,green:CGFloat((v>>8)&0xFF)/255,blue:CGFloat(v&0xFF)/255,alpha:alpha)
    }
    static func dynamic(_ light:NSColor,_ dark:NSColor)->Color {
        Color(nsColor:NSColor(name:nil) {appearance in appearance.bestMatch(from:[.darkAqua,.aqua]) == .darkAqua ? dark:light})
    }
    static func dot(_ project:String)->Color {
        switch project {
        case "P01":return Color(nsColor:.systemBlue)
        case "P02":return Color(nsColor:.systemOrange)
        case "P03":return Color(nsColor:.systemPurple)
        default:return Color(nsColor:.systemTeal)
        }
    }
    static func ink(_ project:String)->Color {
        switch project {
        case "P01":return dynamic(hex(0x0062CC),hex(0x64B5FF))
        case "P02":return dynamic(hex(0xA35400),hex(0xFFB340))
        case "P03":return dynamic(hex(0x8E3FB8),hex(0xDA8FFF))
        default:return dynamic(hex(0x1B7385),hex(0x5AC8DC))
        }
    }
    static let urgentBG=dynamic(hex(0xFFE5E3),hex(0xFF453A,0.22))
    static let urgentFG=dynamic(hex(0xB3261E),hex(0xFF8A80))
    static let soonBG=dynamic(hex(0xFFF0D9),hex(0xFF9F0A,0.20))
    static let soonFG=dynamic(hex(0x8A4E00),hex(0xFFC66B))
    static let neutralBG=Color.primary.opacity(0.06)
    static let rule=Color.primary.opacity(0.08)
    static let track=Color.primary.opacity(0.10)

    static func minutes(_ n:Int)->String {
        if n<60 {return "\(n)m"}
        return n%60==0 ? "\(n/60)h":"\(n/60)h\(n%60)m"
    }
}

// 今日安排的「完成」标记：看板本身不写 workspace.json；标记同步到 ~/Personal Workspace/logs/today-progress.json，
// 由晚间汇报读取并写入数据库。本机状态存在 Application Support/PersonalWorkspace/checks/state.json。
final class PlanChecks:ObservableObject {
    @Published private(set) var done:Set<String>=[]
    private(set) var markedAt:[String:Date]=[:]
    var onChange:(()->Void)?
    private let file:URL
    private struct Stored:Codable {var ids:[String];var at:[String:Date]?}
    init(directory:URL) {
        file=directory.appendingPathComponent("state.json")
        if let data=try? Data(contentsOf:file),let stored=try? JSONDecoder().decode(Stored.self,from:data) {done=Set(stored.ids);markedAt=stored.at ?? [:]}
    }
    func isDone(_ planID:String)->Bool {done.contains(planID)}
    func toggle(_ planID:String,keepPrefix:String) {
        var next=done.filter{$0.hasPrefix(keepPrefix)}   // Plan ID 形如 D20261025-03，只保留当天
        if next.contains(planID) {next.remove(planID)} else {next.insert(planID)}
        markedAt=markedAt.filter{next.contains($0.key)}
        if next.contains(planID) {markedAt[planID]=Date()}
        done=next
        defer {onChange?()}
        do {
            try FileManager.default.createDirectory(at:file.deletingLastPathComponent(),withIntermediateDirectories:true,attributes:[.posixPermissions:0o700])
            try JSONEncoder().encode(Stored(ids:next.sorted(),at:markedAt)).write(to:file,options:.atomic)
            try FileManager.default.setAttributes([.posixPermissions:0o600],ofItemAtPath:file.path)
        } catch {}
    }
}
