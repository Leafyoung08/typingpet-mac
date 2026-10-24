import AppKit

enum SelfTests {
    static func run()->Int32 {
        let root=FileManager.default.temporaryDirectory.appendingPathComponent("TypingPet-tests-\(UUID().uuidString)",isDirectory:true)
        setenv("TYPINGPET_DATA_DIR",root.path,1)
        defer {try? FileManager.default.removeItem(at:root)}
        var count=0
        func check(_ value:@autoclosure ()->Bool,_ message:String) throws {
            guard value() else {throw NSError(domain:"SelfTests",code:1,userInfo:[NSLocalizedDescriptionKey:message])};count+=1
        }
        do {
            _=NSApplication.shared
            try PetFiles.prepare()
            var state=AppState()
            try check(state.pets.count == 1 && state.presets.isEmpty,"默认状态")
            try check(InputTrigger(kind:"key",code:0,modifiers:UInt64(NSEvent.ModifierFlags.command.rawValue)).label == "⌘A","组合键显示")
            try check(InputTrigger(kind:"mouse",code:1).label == "鼠标右键","鼠标标签")
            try check(PetFiles.imageURL("../outside.png") == nil,"阻止图片路径穿越")
            let profile=PetProfile(name:"测试预设")
            state.presets=[profile];state.pets.append(PetPlacement(profileID:profile.id,x:20,y:30))
            try PetFiles.save(state)
            try check(PetFiles.load() == state,"设置和多宠物位置往返保存")
            state.pets.append(PetPlacement(profileID:UUID()))
            state.settings.size=9000;state.settings.opacity=0;state.settings.bounce=100
            try PetFiles.save(state)
            let recovered=PetFiles.load()
            try check(recovered.pets.count == 2,"移除孤立预设宠物")
            try check(recovered.settings.size == 800 && recovered.settings.opacity == 0.15 && recovered.settings.bounce == 18,"校正越界设置")
            let basic=PetImageLoader.load("basic")
            try check(basic != nil && basic!.frames.count == 1,"加载内置 PNG")
            try check(basic!.size.width == 800 && basic!.size.height == 500,"保留原图尺寸")
            guard let imageURL=PetFiles.imageURL("basic") else{throw NSError(domain:"SelfTests",code:2)}
            let imported=try PetImageLoader.validateAndImport(imageURL)
            try check(PetImageLoader.load(imported)?.frames.count == 1,"复制与加载自定义图片")
            let invalid=root.appendingPathComponent("invalid.png");try Data("invalid image".utf8).write(to:invalid)
            var rejected=false
            do {_=try PetImageLoader.validateAndImport(invalid)} catch {rejected=true}
            try check(rejected,"拒绝损坏图片")
            let canvas=PetCanvasView(frame:NSRect(x:0,y:0,width:320,height:220))
            canvas.reset();canvas.input(.down(InputTrigger(code:0)))
            try check(canvas.currentImageName == "left","第一个按键抬左手")
            canvas.input(.down(InputTrigger(code:1)))
            try check(canvas.currentImageName == "right","下一个按键交替抬右手")
            canvas.input(.down(InputTrigger(kind:"mouse",code:0)))
            try check(canvas.currentImageName == "right","未绑定鼠标不触发动作")
            canvas.profile.patterns=[PetPattern(trigger:InputTrigger(kind:"mouse",code:0),image:"pattern1")]
            canvas.input(.down(InputTrigger(kind:"mouse",code:0)))
            try check(canvas.currentImageName == "pattern1","鼠标触发指定图片")
            RunLoop.current.run(until:Date(timeIntervalSinceNow:0.25))
            try check(canvas.currentImageName == "pattern1","鼠标按住时保持图片")
            canvas.input(.up(InputTrigger(kind:"mouse",code:0)))
            RunLoop.current.run(until:Date(timeIntervalSinceNow:0.05))
            try check(canvas.currentImageName == "basic","鼠标松开后回到默认")
            canvas.profile.patterns=[PetPattern(trigger:InputTrigger(code:0,modifiers:UInt64(NSEvent.ModifierFlags.command.rawValue)),image:"pattern2")]
            canvas.input(.down(InputTrigger(code:0)))
            try check(canvas.currentImageName != "pattern2","组合键修饰键准确匹配")
            canvas.input(.down(InputTrigger(code:0,modifiers:UInt64(NSEvent.ModifierFlags.command.rawValue))))
            try check(canvas.currentImageName == "pattern2","组合键触发图片")
            canvas.settings.paused=true;canvas.reset();canvas.input(.down(InputTrigger(code:1)))
            try check(canvas.currentImageName == "basic","暂停后不响应")
            canvas.stop()
            try Data("bad json".utf8).write(to:PetFiles.state)
            let repaired=PetFiles.load()
            try check(repaired.pets.count == 1 && repaired.presets.isEmpty,"损坏设置安全恢复")
            let files=try FileManager.default.contentsOfDirectory(atPath:root.path)
            try check(files.contains(where:{$0.hasPrefix("settings-damaged-")}),"损坏设置备份")
            print("PASS: \(count) checks (settings, images, input reactions, mouse hold, recovery)")
            return 0
        } catch {fputs("FAIL after \(count) checks: \(error.localizedDescription)\n",stderr);return 1}
    }
}
