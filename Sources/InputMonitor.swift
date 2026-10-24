import AppKit
import ApplicationServices

enum InputSignal {
    case down(InputTrigger)
    case up(InputTrigger)
    case pulse(InputTrigger)
}

// Listen-only event tap: key codes and modifier bits only. Never reads text.
final class InputMonitor {
    var onInput: ((InputSignal) -> Void)?
    private var tap: CFMachPort?
    private var source: CFRunLoopSource?
    private var localMonitor: Any?
    private var pendingModifier: Int?
    var isRunning: Bool { tap != nil }
    static var hasPermission: Bool { CGPreflightListenEventAccess() }

    func start() {
        stop()
        pendingModifier = nil
        guard Self.hasPermission else { startLocalFallback(); return }
        let types: [CGEventType] = [.keyDown,.keyUp,.flagsChanged,.leftMouseDown,.leftMouseUp,.rightMouseDown,.rightMouseUp,.otherMouseDown,.otherMouseUp]
        let mask = types.reduce(CGEventMask(0)) { $0 | (1 << $1.rawValue) }
        tap = CGEvent.tapCreate(tap:.cgSessionEventTap, place:.headInsertEventTap, options:.listenOnly, eventsOfInterest:mask, callback: { _, type, event, context in
            guard let context else { return Unmanaged.passUnretained(event) }
            let monitor = Unmanaged<InputMonitor>.fromOpaque(context).takeUnretainedValue()
            if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
                if let tap = monitor.tap { CGEvent.tapEnable(tap:tap, enable:true) }
            } else {
                monitor.handle(type:type, code:Int(event.getIntegerValueField(.keyboardEventKeycode)), flags:event.flags.rawValue, button:Int(event.getIntegerValueField(.mouseEventButtonNumber)))
            }
            return Unmanaged.passUnretained(event)
        }, userInfo:Unmanaged.passUnretained(self).toOpaque())
        guard let tap else { startLocalFallback(); return }
        source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault,tap,0)
        if let source { CFRunLoopAddSource(CFRunLoopGetMain(),source,.commonModes) }
        CGEvent.tapEnable(tap:tap,enable:true)
    }

    private func startLocalFallback() {
        localMonitor = NSEvent.addLocalMonitorForEvents(matching:[.keyDown,.keyUp,.flagsChanged,.leftMouseDown,.leftMouseUp,.rightMouseDown,.rightMouseUp,.otherMouseDown,.otherMouseUp]) { [weak self] event in
            let type: CGEventType
            switch event.type {
            case .keyDown: type = .keyDown
            case .keyUp: type = .keyUp
            case .flagsChanged: type = .flagsChanged
            case .leftMouseDown: type = .leftMouseDown
            case .leftMouseUp: type = .leftMouseUp
            case .rightMouseDown: type = .rightMouseDown
            case .rightMouseUp: type = .rightMouseUp
            case .otherMouseDown: type = .otherMouseDown
            case .otherMouseUp: type = .otherMouseUp
            default: return event
            }
            let keyboard = type == .keyDown || type == .keyUp || type == .flagsChanged
            self?.handle(type:type,code:keyboard ? Int(event.keyCode):0,flags:UInt64(event.modifierFlags.rawValue),button:keyboard ? 0:event.buttonNumber)
            return event
        }
    }

    private func handle(type:CGEventType,code:Int,flags:UInt64,button:Int) {
        let mods = flags & InputTrigger.modifierMask
        switch type {
        case .keyDown:
            pendingModifier = nil
            onInput?(.down(InputTrigger(kind:"key",code:code,modifiers:mods)))
        case .keyUp:
            onInput?(.up(InputTrigger(kind:"key",code:code,modifiers:mods)))
        case .flagsChanged:
            if code == 57 { pendingModifier = nil; onInput?(.pulse(InputTrigger(kind:"modifier",code:code))); return }
            let flag: NSEvent.ModifierFlags
            switch code { case 54,55: flag = .command; case 56,60: flag = .shift; case 58,61: flag = .option; case 59,62: flag = .control; default: return }
            if mods & UInt64(flag.rawValue) != 0 { pendingModifier = code }
            else {
                if pendingModifier == code { onInput?(.pulse(InputTrigger(kind:"modifier",code:code))) }
                pendingModifier = nil
            }
        case .leftMouseDown,.rightMouseDown,.otherMouseDown:
            pendingModifier = nil
            onInput?(.down(InputTrigger(kind:"mouse",code:button)))
        case .leftMouseUp,.rightMouseUp,.otherMouseUp:
            onInput?(.up(InputTrigger(kind:"mouse",code:button)))
        default: break
        }
    }

    func stop() {
        if let tap { CGEvent.tapEnable(tap:tap,enable:false); CFMachPortInvalidate(tap) }
        if let source { CFRunLoopRemoveSource(CFRunLoopGetMain(),source,.commonModes) }
        if let localMonitor { NSEvent.removeMonitor(localMonitor) }
        localMonitor = nil; tap = nil; source = nil; pendingModifier = nil
    }
    deinit { stop() }
}
