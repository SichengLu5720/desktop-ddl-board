import Foundation
var failed=0
func check(_ raw:String,_ text:String,_ tags:[String]) {
    let r=TitleFormatter.format(raw)
    if r.text != text || r.tags != tags {failed+=1;print("FAIL",raw,"→",r.text,r.tags,"expected",text,tags)}
}
check("COURSE101 题目+3篇文献（保守准备日）","Geomorph · 题目+3 篇文献",["准备日"])
check("COURSE101 A1（普通截止；延期待核）","Geomorph · A1",["普通","待核"])
check("COURSE104 论文（普通截止；个人日期待核）","Report · 论文",["普通","待核"])
check("COURSE103 提交测绘项目（RAA截止）","Mapping · 提交测绘项目",["RAA"])
check("COURSE102 预习 Week 4 地面火山监测并准备 practical","Volcanoes · 预习 Week 4 地面火山监测",[])
check("COURSE102 小组确认分工并准备展示","Volcanoes · 小组确认分工并准备展示",[])
check("COURSE104 准备30分钟 viva（日期待公布）","Report · 准备 30 分钟 viva",["待公布"])
check("收集岗位JD：AI产品经理6个＋游戏AI策划/投放各2个，整理能力清单","收集岗位 JD",[])
check("SQL基础（SQLite）：SELECT/WHERE/GROUP BY/JOIN＋每天练习题","SQL 基础",[])
check("确定3位推荐人（至少2位学术）并发送项目清单与截止表","确定 3 位推荐人",[])
check("整理中英文简历，突出mod与AI工具经历","整理中英文简历",[])
check("拆解2个AI产品，写竞品分析（用户、场景、AI能力、体验问题、改进建议）","拆解 2 个 AI 产品，写竞品分析",[])
check("示例大学MSc AI：材料定稿并提交","示例大学 MSc AI · 材料定稿并提交",[])
check("示例学院MSc DS：先修核对后决定并提交（视情况）","示例学院 MSc DS",["视情况"])
check("作品：下载Kaggle Cookie Cats数据，建SQLite库，用SQL算两组1日/7日留存","作品 · 下载 Kaggle Cookie Cats 数据",[])
check("Example Studio 2027暑期实习（Internship）：订阅岗位提醒，12月中起查，预计2月初截止","Example Studio 2027 暑期实习 · 订阅岗位提醒",[])
check("投递 Example Corp Program Manager Intern（3个月，伦敦）","投递 Example Corp Program Manager Intern",[])
check("示例大学MSc Social Data Science（视情况）","示例大学 MSc Social Data Science",["视情况"])
check("SQL窗口函数与常见面试题","SQL 窗口函数与常见面试题",[])
let o=TitleFormatter.display(id:"C101-01",raw:"COURSE101 题目+3篇文献（保守准备日）")
if o.text != "Geomorph · 题目与文献" || o.tags != ["准备日"] {failed+=1;print("FAIL override",o)}
print(failed==0 ? "PASS \(20) title checks":"\(failed) title checks failed")
exit(failed==0 ? 0:1)
