import Foundation

// 看板短标题：主标题只保留「动作 + 对象」，被省略的内容完整保留在悬停提示和任务详情里；
// 截止性质（准备日 / RAA / 普通 / 待核 / 待公布 / 视情况）提取为标签，不会因缩短而丢失。
struct ShortTitle:Equatable {
    let text:String
    let tags:[String]
}

enum TitleFormatter {
    // 规则 0：手动命名优先（按 Task ID）
    // 按 Task ID 手动命名（示例）；自己的任务在这里补充
    static let overrides=[
        "C101-01":"Geomorph · 题目与文献","C101-02":"Geomorph · A1",
        "C104-02":"Report · 阅读与写作","C102-07":"Volcanoes · Week 4 预习"
    ]
    // 课程代码 → 短名（示例代码，换成你自己的）
    static let courses=[("COURSE101","Geomorph"),("COURSE102","Volcanoes"),("COURSE103","Mapping"),("COURSE104","Report")]
    static let tagRules=[("保守准备日","准备日"),("RAA截止","RAA"),("普通截止","普通"),("延期待核|个人日期待核|待核","待核"),("日期待公布","待公布"),("视情况","视情况")]

    private static var cache:[String:NSRegularExpression]=[:]
    private static func re(_ pattern:String)->NSRegularExpression {
        if let r=cache[pattern] {return r}
        let r=try! NSRegularExpression(pattern:pattern);cache[pattern]=r;return r
    }
    private static func whole(_ s:String)->NSRange {NSRange(s.startIndex..<s.endIndex,in:s)}
    static func replace(_ s:String,_ pattern:String,_ template:String)->String {
        re(pattern).stringByReplacingMatches(in:s,range:whole(s),withTemplate:template)
    }
    static func groups(_ s:String,_ pattern:String)->[String]? {
        guard let m=re(pattern).firstMatch(in:s,range:whole(s)) else {return nil}
        return (0..<m.numberOfRanges).map {i in Range(m.range(at:i),in:s).map{String(s[$0])} ?? ""}
    }
    static func captures(_ s:String,_ pattern:String)->[String] {
        re(pattern).matches(in:s,range:whole(s)).compactMap {m in Range(m.range(at:1),in:s).map{String(s[$0])}}
    }
    static func contains(_ s:String,_ pattern:String)->Bool {re(pattern).firstMatch(in:s,range:whole(s)) != nil}

    static func format(_ raw:String)->ShortTitle {
        // 规则 1：统一全角符号与空白
        var s=raw.replacingOccurrences(of:"＋",with:"+").replacingOccurrences(of:"／",with:"/").replacingOccurrences(of:"\u{3000}",with:" ")
        s=replace(s,"\\s+"," ").trimmingCharacters(in:.whitespaces)
        // 规则 2：课程代码 → 课程短名，开头的代码变成「课程 · 」前缀
        var prefix=""
        for (code,name) in courses {
            if contains(s,"^"+code+"\\s*") {prefix=name+" · ";s=replace(s,"^"+code+"\\s*","")}
            s=s.replacingOccurrences(of:code,with:name)
        }
        // 规则 3：括号里的截止性质提取为标签，括号整体移出主标题
        var tags:[String]=[]
        for inner in captures(s,"[（(]([^）)]*)[）)]") {
            for (pattern,label) in tagRules where contains(inner,pattern) && !tags.contains(label) {tags.append(label)}
        }
        s=replace(s,"\\s*[（(][^）)]*[）)]\\s*"," ").trimmingCharacters(in:.whitespaces)
        // 规则 4：「主题：细节」只保留主题；细节首句很短（≤8 字）或主题过短（<4 字）时以「 · 」接上首句
        if let g=groups(s,"^([^：:]{2,}?)\\s*[：:]\\s*(.+)$") {
            let head=g[1],tail=g[2]
            let clause=(tail.components(separatedBy:CharacterSet(charactersIn:"，,；;")).first ?? tail).trimmingCharacters(in:.whitespaces)
            s=(clause.count<=8 || head.count<4) ? head+" · "+clause:head
        } else if let g=groups(s,"^([^，,]{6,}?)[，,].+$"),s.count>18 {
            // 规则 5：无冒号的长标题，保留第一个逗号前的动作
            s=g[1]
        }
        // 规则 6：去掉较长的「并……」后续动作（≥7 字），前半句至少 6 字
        if let g=groups(s,"^(.{6,}?)并.{7,}$") {s=g[1]}
        // 规则 7：中文与字母数字之间加空格
        s=replace(s,"([\\x{4e00}-\\x{9fff}])([A-Za-z0-9])","$1 $2")
        s=replace(s,"([A-Za-z0-9])([\\x{4e00}-\\x{9fff}])","$1 $2")
        return ShortTitle(text:prefix+s.trimmingCharacters(in:.whitespaces),tags:tags)
    }
    /// 看板显示用：手动命名优先，其余按规则缩短；标签始终来自原始任务名。
    static func display(id:String,raw:String)->ShortTitle {
        let auto=format(raw)
        if let name=overrides[id] {return ShortTitle(text:name,tags:auto.tags)}
        return auto
    }
}
