import SwiftUI
import AppKit

final class DailyTimer:ObservableObject {
    @Published private(set) var state:DailyTimerState
    @Published private(set) var saveError:String?
    @Published var displayVisible=true
    var onChange:(()->Void)?
    private let file:URL
    private var boundaryTimer:Timer?
    private var observers:[NSObjectProtocol]=[]
    private var wakeObserver:NSObjectProtocol?
    init(directory:URL,now:Date=Date()) {
        // Keep timer writes out of the snapshot directory's direct file watcher.
        file=directory.appendingPathComponent("state.json")
        state=DailyTimerState(at:now)
        do {
            try FileManager.default.createDirectory(at:directory,withIntermediateDirectories:true,attributes:[.posixPermissions:0o700])
            if FileManager.default.fileExists(atPath:file.path) {
                let restored=try DailyTimerCodec.decode(Data(contentsOf:file))
                guard restored.valid(at:now) else {throw CocoaError(.fileReadCorruptFile)}
                state=restored
                if state.reconcile(at:now) {persist()}
            }
        } catch {saveError="计时记录不可用；点击开始将保存新的计时"}
        scheduleReset()
        wakeObserver=NSWorkspace.shared.notificationCenter.addObserver(forName:NSWorkspace.didWakeNotification,object:nil,queue:.main) { [weak self] _ in self?.reconcile() }
        for name in [Notification.Name.NSSystemClockDidChange,Notification.Name.NSCalendarDayChanged] {
            observers.append(NotificationCenter.default.addObserver(forName:name,object:nil,queue:.main) { [weak self] _ in self?.reconcile() })
        }
    }
    deinit {
        boundaryTimer?.invalidate()
        for observer in observers {NotificationCenter.default.removeObserver(observer)}
        if let observer=wakeObserver {NSWorkspace.shared.notificationCenter.removeObserver(observer)}
    }
    func toggle() {
        state.toggle(at:Date());persist();scheduleReset()
    }
    private func persist() {
        do {
            try DailyTimerCodec.encode(state).write(to:file,options:.atomic)
            try FileManager.default.setAttributes([.posixPermissions:0o600],ofItemAtPath:file.path)
            saveError=nil
        } catch {saveError="计时暂未保存，退出应用可能丢失本次变更"}
        onChange?()
    }
    private func reconcile() {
        if state.reconcile(at:Date()) {persist()} else {objectWillChange.send()}
        scheduleReset()
    }
    private func scheduleReset() {
        boundaryTimer?.invalidate()
        boundaryTimer=Timer.scheduledTimer(withTimeInterval:max(0.1,WorkDayClock.nextReset(after:Date()).timeIntervalSinceNow),repeats:false) { [weak self] _ in self?.reconcile() }
        boundaryTimer?.tolerance=0.5
    }
    var help:String {saveError ?? "点击开始或暂停累计计时；每天 07:00（伦敦时间）归零并暂停。重启后保留进度。"}
}

struct DailyTimerButton:NSViewRepresentable {
    @ObservedObject var timer:DailyTimer
    func makeNSView(context:Context)->TimerControl {TimerControl()}
    func updateNSView(_ view:TimerControl,context:Context) {view.configure(timer)}
    static func dismantleNSView(_ view:TimerControl,coordinator:()) {view.stopDisplay()}
    func sizeThatFits(_ proposal:ProposedViewSize,nsView:TimerControl,context:Context)->CGSize? {CGSize(width:106,height:22)}
}

// A small native drawing surface avoids SwiftUI body/layout work on every frame.
final class TimerControl:NSControl {
    private var record=DailyTimerState(at:Date())
    private var resetAt=WorkDayClock.nextReset(after:Date())
    private var displayTimer:Timer?
    private var displayVisible=true
    private var failed=false
    private weak var model:DailyTimer?
    override var intrinsicContentSize:NSSize {NSSize(width:106,height:22)}
    override var acceptsFirstResponder:Bool {true}
    override func acceptsFirstMouse(for event:NSEvent?)->Bool {true}
    override init(frame:NSRect) {
        super.init(frame:frame)
        setAccessibilityElement(true);setAccessibilityRole(.button)
    }
    required init?(coder:NSCoder) {fatalError("init(coder:) has not been implemented")}
    deinit {displayTimer?.invalidate()}
    func configure(_ model:DailyTimer) {
        self.model=model;record=model.state;failed=model.saveError != nil
        displayVisible=model.displayVisible;resetAt=WorkDayClock.nextReset(after:Date());toolTip=model.help
        updateDisplay();needsDisplay=true
    }
    override func viewDidMoveToWindow() {super.viewDidMoveToWindow();updateDisplay()}
    func stopDisplay() {displayTimer?.invalidate();displayTimer=nil}
    private func updateDisplay() {
        stopDisplay()
        guard record.running,displayVisible,window != nil else {return}
        let ticker=Timer(timeInterval:1.0/30,repeats:true) { [weak self] _ in self?.needsDisplay=true }
        ticker.tolerance=0.005;displayTimer=ticker;RunLoop.main.add(ticker,forMode:.common)
    }
    private var elapsed:TimeInterval {
        let now=Date()
        return now<resetAt ? record.accumulated+max(0,record.startedAt.map{now.timeIntervalSince($0)} ?? 0):0
    }
    override func mouseDown(with event:NSEvent) {model?.toggle()}
    override func keyDown(with event:NSEvent) {
        if event.characters==" " || event.characters=="\r" {model?.toggle()} else {super.keyDown(with:event)}
    }
    override func accessibilityPerformPress()->Bool {model?.toggle();return model != nil}
    override func accessibilityLabel()->String? {record.running ? "暂停今日计时":"开始今日计时"}
    override func accessibilityValue()->Any? {DailyTimerState.display(elapsed)}
    override func draw(_ dirtyRect:NSRect) {
        NSColor.labelColor.withAlphaComponent(0.06).setFill()
        NSBezierPath(roundedRect:bounds,xRadius:11,yRadius:11).fill()
        let color: NSColor = failed ? .systemOrange:(record.running ? .controlAccentColor:.labelColor)
        color.setFill()
        if record.running {
            NSBezierPath(rect:NSRect(x:8,y:7,width:2.5,height:8)).fill()
            NSBezierPath(rect:NSRect(x:12.5,y:7,width:2.5,height:8)).fill()
        } else {
            let play=NSBezierPath();play.move(to:NSPoint(x:8,y:6));play.line(to:NSPoint(x:15,y:11));play.line(to:NSPoint(x:8,y:16));play.close();play.fill()
        }
        let text=DailyTimerState.display(elapsed) as NSString
        let attributes:[NSAttributedString.Key:Any]=[.font:NSFont.monospacedDigitSystemFont(ofSize:11,weight:.medium),.foregroundColor:color]
        let size=text.size(withAttributes:attributes)
        text.draw(at:NSPoint(x:21,y:(bounds.height-size.height)/2),withAttributes:attributes)
        if window?.firstResponder === self {
            NSColor.keyboardFocusIndicatorColor.setStroke()
            let outline=NSBezierPath(roundedRect:bounds.insetBy(dx:1,dy:1),xRadius:10,yRadius:10);outline.lineWidth=1;outline.stroke()
        }
    }
}
