import AppKit

final class PetPanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

final class PetWindowController {
    let id: UUID
    let panel: PetPanel
    let canvas: PetCanvasView
    private var lastProfile: PetProfile?
    var onPosition: ((UUID,NSPoint)->Void)?
    var onFront: ((UUID)->Void)?
    var menuProvider: ((UUID)->NSMenu)?

    init(id:UUID) {
        self.id = id
        panel = PetPanel(contentRect:NSRect(x:0,y:0,width:320,height:220),styleMask:[.borderless,.nonactivatingPanel],backing:.buffered,defer:false)
        canvas = PetCanvasView(frame:NSRect(x:0,y:0,width:320,height:220))
        panel.contentView = canvas
        panel.isOpaque = false; panel.backgroundColor = .clear; panel.hasShadow = false
        panel.hidesOnDeactivate = false; panel.isReleasedWhenClosed = false
        panel.collectionBehavior = [.canJoinAllSpaces,.fullScreenAuxiliary,.stationary,.ignoresCycle]
        panel.isMovableByWindowBackground = false
        panel.title = "Typing Pet"
        canvas.onDrag = { [weak self] event in
            guard let self else { return }
            self.onFront?(self.id)
            self.panel.performDrag(with:event)
            self.onPosition?(self.id,self.panel.frame.origin)
        }
        canvas.menuProvider = { [weak self] in guard let self else {return nil}; return self.menuProvider?(self.id) }
    }

    func configure(profile:PetProfile, settings:PetSettings, placement:PetPlacement, index:Int) {
        let changed = lastProfile != profile
        lastProfile = profile
        canvas.profile = profile
        canvas.settings = settings
        panel.level = settings.alwaysOnTop ? .floating : .normal
        panel.ignoresMouseEvents = settings.locked
        let base = PetImageLoader.load(profile.images["basic"] ?? "basic")
        let ratio = (base?.size.height ?? 500) / max(1,base?.size.width ?? 800)
        let size = NSSize(width:settings.size,height:settings.size * min(4,max(0.15,ratio)) + 20)
        var origin = panel.frame.origin
        if let x = placement.x, let y = placement.y { origin = NSPoint(x:x,y:y) }
        else if let frame = NSScreen.main?.visibleFrame {
            origin = NSPoint(x:frame.maxX-size.width-32-Double(index)*40,y:frame.minY+24+Double(index)*18)
        }
        let frames = NSScreen.screens.map(\.visibleFrame)
        // Recover saved positions when a monitor is unplugged; keep the pet reachable.
        let proposed = NSRect(origin:origin,size:size)
        if !frames.contains(where: { $0.intersection(proposed).width >= min(60,size.width) && $0.intersection(proposed).height >= min(40,size.height) }), let frame = NSScreen.main?.visibleFrame {
            origin = NSPoint(x:frame.maxX-size.width-24,y:frame.minY+24)
        }
        panel.setFrame(NSRect(origin:origin,size:size),display:true)
        canvas.frame = NSRect(origin:.zero,size:size)
        if changed { canvas.reset() }
        canvas.updateAppearance()
    }
    func input(_ signal:InputSignal) { canvas.input(signal) }
    func close() { canvas.stop(); panel.orderOut(nil); panel.close() }
}

final class PetCanvasView: NSView {
    var profile = PetProfile()
    var settings = PetSettings()
    var onDrag: ((NSEvent)->Void)?
    var menuProvider: (()->NSMenu?)?
    private var tracking: NSTrackingArea?
    private var hover = false
    private var animation: PetAnimation?
    private var animationStart = 0.0
    private var bounceStart = -1.0
    private var timer: Timer?
    private var restore: DispatchWorkItem?
    private var held: InputTrigger?
    private var alternate = false
    private(set) var currentImageName = "basic"

    override var acceptsFirstResponder: Bool { false }
    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let tracking {removeTrackingArea(tracking)}
        let next = NSTrackingArea(rect:.zero,options:[.mouseEnteredAndExited,.activeAlways,.inVisibleRect],owner:self,userInfo:nil)
        addTrackingArea(next); tracking = next
    }
    override func mouseEntered(with event:NSEvent) { hover = true; updateAppearance() }
    override func mouseExited(with event:NSEvent) { hover = false; updateAppearance() }
    override func mouseDown(with event:NSEvent) { onDrag?(event) }
    override func rightMouseDown(with event:NSEvent) {
        if let menu = menuProvider?() { NSMenu.popUpContextMenu(menu,with:event,for:self) }
    }

    func updateAppearance() {
        window?.alphaValue = settings.opacity * (hover && settings.fadeOnHover && !settings.locked ? 0.35 : 1)
        if settings.paused { reset() }
        needsDisplay = true
    }
    func reset() {
        restore?.cancel(); restore = nil; held = nil; bounceStart = -1
        show(profile.images["basic"] ?? "basic")
    }
    private func show(_ name:String) {
        currentImageName = name
        animation = PetImageLoader.load(name) ?? PetImageLoader.load("basic")
        animationStart = Date.timeIntervalSinceReferenceDate
        needsDisplay = true
        updateTimer()
    }
    private func updateTimer() {
        let motion = !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion && settings.bounce > 0 && bounceStart > 0
        let needsTimer = (animation?.frames.count ?? 0) > 1 || motion
        guard needsTimer else { timer?.invalidate(); timer = nil; return }
        if timer == nil {
            timer = Timer(timeInterval:1.0/60.0,repeats:true) { [weak self] _ in
                guard let self else { return }
                if self.bounceStart > 0 && Date.timeIntervalSinceReferenceDate-self.bounceStart > 0.18 { self.bounceStart = -1; self.updateTimer() }
                self.needsDisplay = true
            }
            RunLoop.main.add(timer!,forMode:.common)
        }
    }
    private func restoreAfter(_ duration:Double) {
        restore?.cancel()
        let item = DispatchWorkItem { [weak self] in
            guard let self else {return}
            self.held = nil; self.show(self.profile.images["basic"] ?? "basic")
        }
        restore = item
        DispatchQueue.main.asyncAfter(deadline:.now()+duration,execute:item)
    }
    func input(_ signal:InputSignal) {
        guard !settings.paused else {return}
        let trigger:InputTrigger
        let pulse:Bool
        switch signal {
        case .up(let key):
            if let held, held.kind == key.kind && held.code == key.code { self.held = nil;restoreAfter(key.kind == "mouse" ? 0.02 : 0.10) }
            return
        case .down(let key): trigger = key; pulse = false
        case .pulse(let key): trigger = key; pulse = true
        }
        let pattern = profile.patterns.first(where: {$0.trigger == trigger})
        if trigger.kind == "mouse" && pattern == nil { return }
        // Autorepeat on a held rule must not restart its GIF/APNG on every repeat.
        if let pattern,held == trigger,currentImageName == pattern.image {return}
        restore?.cancel(); restore = nil
        held = pattern != nil ? trigger : nil
        if let pattern { show(pattern.image) }
        else { alternate.toggle(); show(profile.images[alternate ? "left" : "right"] ?? (alternate ? "left" : "right")) }
        if !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion && settings.bounce > 0 { bounceStart = Date.timeIntervalSinceReferenceDate; updateTimer() }
        if pattern == nil || pulse { restoreAfter(0.14) }
    }
    override func draw(_ dirtyRect:NSRect) {
        super.draw(dirtyRect)
        guard let animation, !animation.frames.isEmpty else {return}
        var frameIndex = 0
        if animation.frames.count > 1 && animation.totalDuration > 0 {
            var elapsed = (Date.timeIntervalSinceReferenceDate-animationStart).truncatingRemainder(dividingBy:animation.totalDuration)
            for (index,duration) in animation.durations.enumerated() {
                if elapsed < duration {frameIndex = index;break}
                elapsed -= duration
            }
        }
        var lift = 0.0
        if bounceStart > 0 {
            let t = min(1,max(0,(Date.timeIntervalSinceReferenceDate-bounceStart)/0.18))
            lift = sin(t * .pi) * settings.bounce
        }
        let image = animation.frames[min(frameIndex,animation.frames.count-1)]
        let available = NSRect(x:0,y:lift,width:bounds.width,height:max(1,bounds.height-20))
        let scale = min(available.width/max(1,image.size.width),available.height/max(1,image.size.height))
        let target = NSRect(x:available.midX-image.size.width*scale/2,y:available.midY-image.size.height*scale/2,width:image.size.width*scale,height:image.size.height*scale)
        image.draw(in:target,from:.zero,operation:.sourceOver,fraction:1,respectFlipped:true,hints:[.interpolation:NSImageInterpolation.high])
    }
    func stop() {timer?.invalidate();timer = nil;restore?.cancel();restore = nil}
    deinit { stop() }
}
