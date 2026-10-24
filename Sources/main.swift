import AppKit

if ProcessInfo.processInfo.arguments.contains("--self-test") {
    exit(SelfTests.run())
}
let application = NSApplication.shared
let controller = AppController()
application.delegate = controller
application.run()
