import AppKit
import Combine
import ServiceManagement
import UniformTypeIdentifiers

private final class MenuAction: NSObject {
    let action: ()->Void
    init(_ action:@escaping ()->Void) {self.action = action}
    @objc func invoke() {action()}
}

private struct PetArchive: Codable {
    var format = "typingpet.mac.preset.v1"
    var profile: PetProfile
    var assets: [String:Data]
}

final class AppController: NSObject, NSApplicationDelegate, ObservableObject, NSMenuDelegate {
    @Published var state = PetFiles.load()
    @Published var permissionGranted = InputMonitor.hasPermission
    @Published var capturePatternID: UUID?
    @Published var launchAtLogin = SMAppService.mainApp.status == .enabled
    private let inputMonitor = InputMonitor()
    private var petWindows: [UUID:PetWindowController] = [:]
    private var settingsWindow: SettingsWindowController?
    private var statusItem: NSStatusItem?
    private var permissionTimer: Timer?
    private var captureReady = 0.0
    private var firstSaveError = true
    private var previewJobs: [DispatchWorkItem] = []
    private var workspaceTokens: [NSObjectProtocol] = []

    func applicationDidFinishLaunching(_ notification:Notification) {
        let firstLaunch = !FileManager.default.fileExists(atPath:PetFiles.state.path)
        NSApp.setActivationPolicy(.accessory)
        configureApplicationMenu()
        statusItem = NSStatusBar.system.statusItem(withLength:NSStatusItem.squareLength)
        statusItem?.button?.image = NSImage(systemSymbolName:"pawprint.fill",accessibilityDescription:"Typing Pet")
        statusItem?.button?.toolTip = "Typing Pet — 打字桌面宠物"
        let menu = NSMenu(); menu.delegate = self; statusItem?.menu = menu
        inputMonitor.onInput = { [weak self] signal in self?.receive(signal) }
        inputMonitor.start()
        permissionGranted = InputMonitor.hasPermission && inputMonitor.isRunning
        updateWindows()
        permissionTimer = Timer.scheduledTimer(withTimeInterval:2,repeats:true) { [weak self] _ in self?.refreshPermission() }
        let center = NSWorkspace.shared.notificationCenter
        workspaceTokens.append(center.addObserver(forName:NSWorkspace.didWakeNotification,object:nil,queue:.main) { [weak self] _ in self?.inputMonitor.start(); self?.updateWindows() })
        NotificationCenter.default.addObserver(self,selector:#selector(screenChanged),name:NSApplication.didChangeScreenParametersNotification,object:nil)
        persist()
        let isLogin = ProcessInfo.processInfo.arguments.contains("--login") || NSAppleEventManager.shared().currentAppleEvent?.paramDescriptor(forKeyword:keyAEPropData)?.enumCodeValue == keyAELaunchedAsLogInItem
        if firstLaunch && !isLogin { showSettings() }
        if let path = argument(after:"--render-settings") {
            showSettings()
            DispatchQueue.main.asyncAfter(deadline:.now()+1) { [weak self] in self?.captureSettings(to:path); NSApp.terminate(nil) }
        } else if ProcessInfo.processInfo.arguments.contains("--smoke-test") {
            preview()
            DispatchQueue.main.asyncAfter(deadline:.now()+1.5) { [weak self] in
                print("SMOKE OK: pets=\(self?.petWindows.count ?? 0), permission=\(self?.permissionGranted ?? false)")
                NSApp.terminate(nil)
            }
        }
    }
    private func argument(after value:String)->String? {let args = ProcessInfo.processInfo.arguments;guard let i=args.firstIndex(of:value),i+1<args.count else{return nil};return args[i+1]}
    func applicationWillTerminate(_ notification:Notification) {
        inputMonitor.stop(); permissionTimer?.invalidate(); persist()
        for token in workspaceTokens { NSWorkspace.shared.notificationCenter.removeObserver(token) }
        for window in petWindows.values { window.close() }
    }
    func applicationShouldHandleReopen(_ sender:NSApplication,hasVisibleWindows flag:Bool)->Bool {showSettings();return true}
    @objc private func screenChanged() { updateWindows() }

    func edit(_ body:(inout AppState)->Void) {
        body(&state)
        state.settings.size = min(800,max(120,state.settings.size))
        state.settings.opacity = min(1,max(0.15,state.settings.opacity))
        state.settings.bounce = min(18,max(0,state.settings.bounce))
        persist(); updateWindows()
    }
    private func persist() {
        do {try PetFiles.save(state);firstSaveError = true}
        catch {PetFiles.log("设置保存失败：\(error.localizedDescription)");if firstSaveError {firstSaveError = false;showError("设置未能保存",error.localizedDescription)}}
    }
    private func profile(for placement:PetPlacement)->PetProfile? {
        if let id = placement.profileID {return state.presets.first(where:{$0.id == id})}
        return state.current
    }
    private func updateWindows() {
        var positionsChanged = false
        let valid = Set(state.pets.map(\.id))
        for id in Array(petWindows.keys) where !valid.contains(id) {petWindows.removeValue(forKey:id)?.close()}
        for (index,placement) in state.pets.enumerated() {
            guard let profile = profile(for:placement) else {continue}
            let window:PetWindowController
            if let existing = petWindows[placement.id] {window = existing}
            else {
                window = PetWindowController(id:placement.id);petWindows[placement.id] = window
                window.onPosition = { [weak self] id,point in self?.savePosition(id:id,point:point) }
                window.onFront = { [weak self] id in self?.bringForward(id:id) }
                window.menuProvider = { [weak self] id in self?.makeMenu(petID:id) ?? NSMenu() }
            }
            window.configure(profile:profile,settings:state.settings,placement:placement,index:index)
            let origin = window.panel.frame.origin
            if placement.x != origin.x || placement.y != origin.y {
                state.pets[index].x = origin.x;state.pets[index].y = origin.y;positionsChanged = true
            }
        }
        for placement in state.pets.reversed() {petWindows[placement.id]?.panel.orderFrontRegardless()}
        if positionsChanged {persist()}
    }
    private func savePosition(id:UUID,point:NSPoint) {
        guard let i=state.pets.firstIndex(where:{$0.id == id}) else{return}
        state.pets[i].x = point.x;state.pets[i].y = point.y;persist()
    }
    private func bringForward(id:UUID) {
        guard let i=state.pets.firstIndex(where:{$0.id == id}) else{return}
        let pet=state.pets.remove(at:i);state.pets.insert(pet,at:0);persist()
        petWindows[id]?.panel.orderFrontRegardless()
    }
    func moveLayer(id:UUID,delta:Int) {
        guard let i=state.pets.firstIndex(where:{$0.id == id}) else{return}
        let destination=i+delta
        guard state.pets.indices.contains(destination) else{return}
        edit {$0.pets.swapAt(i,destination)}
    }
    func resetPositions() {edit {state in for i in state.pets.indices {state.pets[i].x=nil;state.pets[i].y=nil}}}
    func showSettings() {
        if settingsWindow == nil {settingsWindow = SettingsWindowController(controller:self)}
        settingsWindow?.present()
    }
    func refreshPermission() {
        let granted = InputMonitor.hasPermission
        if granted != permissionGranted || (granted && !inputMonitor.isRunning) {
            inputMonitor.start();permissionGranted = granted && inputMonitor.isRunning
        }
        let login = SMAppService.mainApp.status == .enabled
        if launchAtLogin != login {launchAtLogin = login}
    }
    func requestInputPermission() {_ = CGRequestListenEventAccess();refreshPermission();if !permissionGranted {openPrivacySettings()}}
    func openPrivacySettings() {
        if let url=URL(string:"x-apple.systempreferences:com.apple.preference.security?Privacy_ListenEvent") {NSWorkspace.shared.open(url)}
    }
    func setLogin(_ enabled:Bool) {
        do {
            if enabled {try SMAppService.mainApp.register()} else {try SMAppService.mainApp.unregister()}
            launchAtLogin = SMAppService.mainApp.status == .enabled
            if enabled && !launchAtLogin {showError("需要在系统设置中允许登录项","请在系统设置 → 通用 → 登录项中检查 Typing Pet。建议先将应用移到“应用程序”文件夹。")}
        } catch {launchAtLogin = SMAppService.mainApp.status == .enabled;showError("无法修改登录项",error.localizedDescription + "\n请先把应用移到“应用程序”文件夹再试。")}
    }
    func showDataFolder() {try? PetFiles.prepare();NSWorkspace.shared.open(PetFiles.root)}

    private func receive(_ signal:InputSignal) {
        if let id=capturePatternID {
            guard Date.timeIntervalSinceReferenceDate >= captureReady else{return}
            let trigger:InputTrigger
            switch signal {case .down(let t),.pulse(let t):trigger=t;case .up:return}
            // Recorder controls must remain clickable without becoming a mouse binding.
            if trigger.kind == "mouse",let window=settingsWindow?.window,window.isVisible,window.frame.contains(NSEvent.mouseLocation) {return}
            if trigger.kind == "key" && trigger.code == 53 && trigger.modifiers == 0 {cancelCapture();return}
            capturePatternID=nil
            guard let index=state.current.patterns.firstIndex(where:{$0.id == id}) else{return}
            if state.current.patterns.contains(where:{$0.id != id && $0.trigger == trigger}) {showError("触发器已被使用","请选择其他按键、组合键或鼠标按钮。");return}
            edit {$0.current.patterns[index].trigger=trigger}
            return
        }
        for window in petWindows.values {window.input(signal)}
    }
    func recordPattern(id:UUID) {captureReady=Date.timeIntervalSinceReferenceDate+0.30;capturePatternID=id}
    func cancelCapture() {capturePatternID=nil}
    func preview() {
        previewJobs.forEach {$0.cancel()};previewJobs=[]
        for i in 0..<8 {
            let job=DispatchWorkItem { [weak self] in
                guard let self else{return}
                for window in self.petWindows.values {window.input(.down(InputTrigger(kind:"key",code:i%2 == 0 ? 0 : 1)))}
            }
            previewJobs.append(job);DispatchQueue.main.asyncAfter(deadline:.now()+Double(i)*0.18,execute:job)
        }
    }
    private func selectImage(_ completion:(String)->Void) {
        let panel=NSOpenPanel();panel.title="选择宠物图片";panel.message="支持 PNG、JPG、GIF、APNG；单张最多 15 MB、300 帧。"
        panel.allowedContentTypes=[.png,.jpeg,.gif,UTType(filenameExtension:"apng") ?? .image];panel.allowsMultipleSelection=false
        NSApp.activate(ignoringOtherApps:true)
        guard panel.runModal() == .OK,let url=panel.url else{return}
        do {let name=try PetImageLoader.validateAndImport(url);completion(name)} catch {showError("无法使用这张图片",error.localizedDescription)}
    }
    func chooseImage(role:String) {selectImage {name in edit {$0.current.images[role]=name}}}
    func resetImage(role:String) {edit {$0.current.images[role]=role}}
    func choosePatternImage(id:UUID) {
        selectImage {name in guard let i=state.current.patterns.firstIndex(where:{$0.id == id}) else{return};edit {$0.current.patterns[i].image=name}}
    }
    func addPattern() {
        guard state.current.patterns.count<20 else{showError("已达到 20 个动作","请先移除一个动作。");return}
        let candidates=[49,36,48,123,124,125,126,0,1,2,3,4,5,6,7,8,9,11,12,13,14,15]
        guard let code=candidates.first(where:{code in !state.current.patterns.contains(where:{$0.trigger == InputTrigger(kind:"key",code:code)})}) else{return}
        let pattern=PetPattern(trigger:InputTrigger(kind:"key",code:code),image:state.current.patterns.count%2 == 0 ? "pattern1":"pattern2")
        edit {$0.current.patterns.append(pattern)}
    }
    func removePattern(id:UUID) {if capturePatternID == id {cancelCapture()};edit {$0.current.patterns.removeAll(where:{$0.id == id})}}
    func savePreset(name:String) {
        let name=String(name.trimmingCharacters(in:.whitespacesAndNewlines).prefix(16))
        guard !name.isEmpty else{showError("请输入预设名称","预设名称最多 16 个字符。");return}
        if let index=state.presets.firstIndex(where:{$0.name == name}) {
            let alert=NSAlert();alert.messageText="覆盖“\(name)”？";alert.informativeText="将使用当前图片和动作替换这个预设。";alert.addButton(withTitle:"覆盖");alert.addButton(withTitle:"取消")
            guard alert.runModal() == .alertFirstButtonReturn else{return}
            var profile=state.current;profile.id=state.presets[index].id;profile.name=name;edit {$0.presets[index]=profile}
        } else {
            guard state.presets.count<10 else{showError("已达到 10 个预设","请先删除一个预设，或使用已有名称覆盖保存。");return}
            var profile=state.current;profile.id=UUID();profile.name=name;edit {$0.presets.append(profile)}
        }
    }
    func applyPreset(id:UUID) {guard var profile=state.presets.first(where:{$0.id == id}) else{return};profile.id=state.current.id;cancelCapture();edit {$0.current=profile}}
    func renamePreset(id:UUID,name:String) {
        let value=String(name.trimmingCharacters(in:.whitespacesAndNewlines).prefix(16))
        guard !value.isEmpty,let i=state.presets.firstIndex(where:{$0.id == id}) else{return}
        guard !state.presets.contains(where:{$0.id != id && $0.name == value}) else{showError("预设名称重复","请使用其他名称。");return}
        edit {$0.presets[i].name=value}
    }
    func deletePreset(id:UUID) {
        guard let profile=state.presets.first(where:{$0.id == id}) else{return}
        let alert=NSAlert();alert.messageText="删除“\(profile.name)”？";alert.informativeText="对应的额外宠物也会隐藏。主宠物当前的图片不受影响。";alert.addButton(withTitle:"删除");alert.addButton(withTitle:"取消")
        guard alert.runModal() == .alertFirstButtonReturn else{return}
        edit {$0.presets.removeAll(where:{$0.id == id});$0.pets.removeAll(where:{$0.profileID == id})}
    }
    func togglePet(profileID:UUID) {
        if state.pets.contains(where:{$0.profileID == profileID}) {edit {$0.pets.removeAll(where:{$0.profileID == profileID})};return}
        guard state.pets.count<4 else{showError("最多同时显示 4 只宠物","请先隐藏一只额外宠物。");return}
        guard state.presets.contains(where:{$0.id == profileID}) else{return}
        edit {$0.pets.insert(PetPlacement(profileID:profileID),at:0)}
    }

    func exportPreset(id:UUID) {
        guard let profile=state.presets.first(where:{$0.id == id}) else{return}
        let panel=NSSavePanel();panel.title="导出 Mac 版预设";panel.nameFieldStringValue="\(profile.name).typingpet";panel.allowedContentTypes=[UTType(filenameExtension:"typingpet") ?? .data]
        guard panel.runModal() == .OK,let url=panel.url else{return}
        do {
            var assets:[String:Data]=[:]
            for name in Set(Array(profile.images.values)+profile.patterns.map(\.image)) where !["basic","left","right","pattern1","pattern2"].contains(name) {
                guard let imageURL=PetFiles.imageURL(name) else{throw archiveError("预设包含无效图片路径。")}
                assets[name]=try Data(contentsOf:imageURL)
            }
            try JSONEncoder().encode(PetArchive(profile:profile,assets:assets)).write(to:url,options:.atomic)
        } catch {showError("预设导出失败",error.localizedDescription)}
    }
    func importPreset() {
        guard state.presets.count<10 else{showError("已达到 10 个预设","请先删除一个预设。");return}
        let panel=NSOpenPanel();panel.title="导入 Mac 版预设";panel.message="请选择本 Mac 版导出的 .typingpet 文件。Windows ZIP 预设暂不兼容。";panel.allowedContentTypes=[UTType(filenameExtension:"typingpet") ?? .data];panel.allowsMultipleSelection=false
        guard panel.runModal() == .OK,let url=panel.url else{return}
        var imported:[String]=[]
        do {
            let size=(try FileManager.default.attributesOfItem(atPath:url.path)[.size] as? NSNumber)?.intValue ?? 0
            guard size>0,size<360*1024*1024 else{throw archiveError("预设文件过大或为空。")}
            let archive=try JSONDecoder().decode(PetArchive.self,from:Data(contentsOf:url))
            guard archive.format == "typingpet.mac.preset.v1",archive.profile.patterns.count<=20,archive.assets.count<=23 else{throw archiveError("预设格式无效或超出数量限制。")}
            var profile=archive.profile;profile.id=UUID();profile.name=String(profile.name.prefix(16));if profile.name.isEmpty {profile.name="导入的宠物"}
            guard Set(profile.patterns.map(\.trigger)).count == profile.patterns.count,profile.patterns.allSatisfy({["key","mouse","modifier"].contains($0.trigger.kind) && $0.trigger.code>=0 && $0.trigger.code<=255 && $0.trigger.modifiers & ~InputTrigger.modifierMask == 0}) else{throw archiveError("预设包含无效或重复触发器。")}
            var mapping:[String:String]=[:]
            let builtin=Set(["basic","left","right","pattern1","pattern2"])
            for name in Set(Array(profile.images.values)+profile.patterns.map(\.image)) where !builtin.contains(name) {
                guard name == URL(fileURLWithPath:name).lastPathComponent,let data=archive.assets[name],data.count<=15*1024*1024 else{throw archiveError("预设的图片缺失或无效。")}
                let temp=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).appendingPathExtension(URL(fileURLWithPath:name).pathExtension)
                defer {try? FileManager.default.removeItem(at:temp)}
                try data.write(to:temp)
                let newName=try PetImageLoader.validateAndImport(temp);mapping[name]=newName;imported.append(newName)
            }
            for (role,name) in profile.images {profile.images[role]=mapping[name] ?? name}
            for i in profile.patterns.indices {profile.patterns[i].id=UUID();profile.patterns[i].image=mapping[profile.patterns[i].image] ?? profile.patterns[i].image}
            if state.presets.contains(where:{$0.name == profile.name}) {profile.name=String(profile.name.prefix(12))+" (2)"}
            edit {$0.presets.append(profile)}
        } catch {
            for name in imported {if let path=PetFiles.imageURL(name) {try? FileManager.default.removeItem(at:path)}}
            showError("预设导入失败",error.localizedDescription)
        }
    }
    private func archiveError(_ text:String)->NSError {NSError(domain:"TypingPet",code:1,userInfo:[NSLocalizedDescriptionKey:text])}
    private func showError(_ title:String,_ detail:String) {let alert=NSAlert();alert.messageText=title;alert.informativeText=detail;alert.addButton(withTitle:"好");NSApp.activate(ignoringOtherApps:true);alert.runModal()}

    func menuNeedsUpdate(_ menu:NSMenu) {let fresh=makeMenu(petID:nil);menu.removeAllItems();for item in fresh.items {fresh.removeItem(item);menu.addItem(item)}}
    private func item(_ title:String,checked:Bool?=nil,key:String="",action:@escaping ()->Void)->NSMenuItem {
        let item=NSMenuItem(title:title,action:#selector(MenuAction.invoke),keyEquivalent:key);let target=MenuAction(action);item.target=target;item.representedObject=target
        if let checked {item.state=checked ? .on:.off};return item
    }
    private func makeMenu(petID:UUID?)->NSMenu {
        let menu=NSMenu()
        menu.addItem(item("设置…",key:",") { [weak self] in self?.showSettings() })
        menu.addItem(item("试试打字动作") { [weak self] in self?.preview() })
        if !permissionGranted {menu.addItem(item("允许输入监控…") { [weak self] in self?.requestInputPermission() })}
        menu.addItem(.separator())
        menu.addItem(item("暂停响应",checked:state.settings.paused) { [weak self] in self?.edit {$0.settings.paused.toggle()} })
        menu.addItem(item("始终置顶",checked:state.settings.alwaysOnTop) { [weak self] in self?.edit {$0.settings.alwaysOnTop.toggle()} })
        menu.addItem(item("锁定位置（鼠标穿透）",checked:state.settings.locked) { [weak self] in self?.edit {$0.settings.locked.toggle()} })
        let sizes=NSMenu();for (name,width) in [("小",220.0),("中",320.0),("大",440.0),("特大",580.0)] {sizes.addItem(item(name,checked:abs(state.settings.size-width)<1) { [weak self] in self?.edit {$0.settings.size=width} })}
        let sizeItem=NSMenuItem(title:"宠物大小",action:nil,keyEquivalent:"");sizeItem.submenu=sizes;menu.addItem(sizeItem)
        menu.addItem(item("重置所有位置") { [weak self] in self?.resetPositions() })
        if let petID {
            menu.addItem(item("移到最前") { [weak self] in self?.bringForward(id:petID) })
            if let profileID=state.pets.first(where:{$0.id == petID})?.profileID {menu.addItem(item("隐藏这只宠物") { [weak self] in self?.togglePet(profileID:profileID) })}
        }
        menu.addItem(.separator());menu.addItem(item("退出 Typing Pet",key:"q") {NSApp.terminate(nil)})
        return menu
    }
    private func configureApplicationMenu() {
        let main=NSMenu();let app=NSMenuItem();main.addItem(app);let sub=NSMenu();app.submenu=sub
        sub.addItem(item("设置…",key:",") { [weak self] in self?.showSettings() });sub.addItem(item("退出 Typing Pet",key:"q") {NSApp.terminate(nil)})
        let edit=NSMenuItem();edit.title="编辑";let editMenu=NSMenu(title:"编辑");edit.submenu=editMenu
        for (title,selector,key) in [("撤销",Selector(("undo:")),"z"),("剪切",#selector(NSText.cut(_:)),"x"),("复制",#selector(NSText.copy(_:)),"c"),("粘贴",#selector(NSText.paste(_:)),"v"),("全选",#selector(NSText.selectAll(_:)),"a")] {editMenu.addItem(NSMenuItem(title:title,action:selector,keyEquivalent:key))}
        main.addItem(edit);NSApp.mainMenu=main
    }
    private func captureSettings(to path:String) {
        guard let view=settingsWindow?.window?.contentView,let bitmap=view.bitmapImageRepForCachingDisplay(in:view.bounds) else{return}
        view.cacheDisplay(in:view.bounds,to:bitmap)
        if let data=bitmap.representation(using:.png,properties:[:]) {try? data.write(to:URL(fileURLWithPath:path))}
    }
}
