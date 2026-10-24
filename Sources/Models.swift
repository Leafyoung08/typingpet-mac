import AppKit
import Combine

struct InputTrigger: Codable, Equatable, Hashable {
    var kind: String = "key"
    var code: Int = 0
    var modifiers: UInt64 = 0
    var label: String { Self.describe(kind: kind, code: code, modifiers: modifiers) }
    static let modifierMask = UInt64(NSEvent.ModifierFlags([.command, .shift, .control, .option]).rawValue)
    static func describe(kind: String, code: Int, modifiers: UInt64) -> String {
        if kind == "mouse" { return [0: "鼠标左键", 1: "鼠标右键", 2: "鼠标中键"][code] ?? "鼠标键 \(code + 1)" }
        let keys: [Int: String] = [0:"A",1:"S",2:"D",3:"F",4:"H",5:"G",6:"Z",7:"X",8:"C",9:"V",11:"B",12:"Q",13:"W",14:"E",15:"R",16:"Y",17:"T",18:"1",19:"2",20:"3",21:"4",22:"6",23:"5",24:"=",25:"9",26:"7",27:"−",28:"8",29:"0",30:"]",31:"O",32:"U",33:"[",34:"I",35:"P",36:"Return",37:"L",38:"J",39:"'",40:"K",41:";",42:"\\",43:",",44:"/",45:"N",46:"M",47:".",48:"Tab",49:"Space",50:"`",51:"Delete",53:"Esc",54:"⌘",55:"⌘",56:"⇧",57:"Caps Lock",58:"⌥",59:"⌃",60:"⇧",61:"⌥",62:"⌃",65:"数字键盘 .",67:"数字键盘 *",69:"数字键盘 +",71:"Clear",75:"数字键盘 /",76:"Enter",78:"数字键盘 −",81:"数字键盘 =",82:"数字键盘 0",83:"数字键盘 1",84:"数字键盘 2",85:"数字键盘 3",86:"数字键盘 4",87:"数字键盘 5",88:"数字键盘 6",89:"数字键盘 7",91:"数字键盘 8",92:"数字键盘 9",96:"F5",97:"F6",98:"F7",99:"F3",100:"F8",101:"F9",103:"F11",109:"F10",111:"F12",115:"Home",116:"Page Up",117:"向前删除",118:"F4",119:"End",120:"F2",121:"Page Down",122:"F1",123:"←",124:"→",125:"↓",126:"↑"]
        if kind == "modifier" { return keys[code] ?? "修饰键" }
        var prefix = ""
        for (flag, glyph) in [(NSEvent.ModifierFlags.control,"⌃"),(.option,"⌥"),(.shift,"⇧"),(.command,"⌘")] where modifiers & UInt64(flag.rawValue) != 0 { prefix += glyph }
        return prefix + (keys[code] ?? "Key \(code)")
    }
}

struct PetPattern: Codable, Equatable, Identifiable {
    var id = UUID()
    var trigger = InputTrigger()
    var image = "pattern1"
}

struct PetProfile: Codable, Equatable, Identifiable {
    var id = UUID()
    var name = "默认宠物"
    // Built-in names or a filename relative to Application Support/Images.
    var images: [String: String] = ["basic":"basic", "left":"left", "right":"right"]
    var patterns: [PetPattern] = []
}

struct PetSettings: Codable, Equatable {
    var size = 320.0
    var bounce = 8.0
    var alwaysOnTop = true
    var locked = false
    var opacity = 1.0
    var fadeOnHover = true
    var paused = false
}

struct PetPlacement: Codable, Equatable, Identifiable {
    var id = UUID()
    var profileID: UUID? = nil
    var x: Double? = nil
    var y: Double? = nil
}

struct AppState: Codable, Equatable {
    var version = 1
    var settings = PetSettings()
    var current = PetProfile()
    var presets: [PetProfile] = []
    // Frontmost first. A nil profileID denotes the main pet.
    var pets: [PetPlacement] = [PetPlacement()]
}

enum PetFiles {
    static var root: URL {
        if let path = ProcessInfo.processInfo.environment["TYPINGPET_DATA_DIR"] { return URL(fileURLWithPath:path, isDirectory:true) }
        return FileManager.default.urls(for:.applicationSupportDirectory, in:.userDomainMask)[0].appendingPathComponent("TypingPetMac", isDirectory:true)
    }
    static var images: URL { root.appendingPathComponent("Images", isDirectory:true) }
    static var state: URL { root.appendingPathComponent("settings.json") }
    static func prepare() throws { try FileManager.default.createDirectory(at:images, withIntermediateDirectories:true) }
    static func imageURL(_ name: String) -> URL? {
        if ["basic", "left", "right", "pattern1", "pattern2"].contains(name) {
            return Bundle.main.resourceURL?.appendingPathComponent("images/\(name).png")
        }
        guard name == URL(fileURLWithPath:name).lastPathComponent, !name.hasPrefix(".") else { return nil }
        return images.appendingPathComponent(name)
    }
    static func load() -> AppState {
        guard FileManager.default.fileExists(atPath:state.path) else { return AppState() }
        do {
            var result = try JSONDecoder().decode(AppState.self, from:Data(contentsOf:state))
            result.settings.size = min(800,max(120,result.settings.size))
            result.settings.opacity = min(1,max(0.15,result.settings.opacity))
            result.settings.bounce = min(18,max(0,result.settings.bounce))
            result.presets = Array(result.presets.prefix(10))
            result.current.patterns = Array(result.current.patterns.prefix(20))
            var profileIDs = Set<UUID>()
            result.presets = result.presets.filter { profileIDs.insert($0.id).inserted }
            for index in result.presets.indices { result.presets[index].patterns = Array(result.presets[index].patterns.prefix(20)) }
            var seenPets = Set<UUID>()
            var seenProfiles = Set<UUID>()
            var hasMain = false
            result.pets = result.pets.filter { placement in
                guard seenPets.insert(placement.id).inserted else {return false}
                if let id=placement.profileID {return profileIDs.contains(id) && seenProfiles.insert(id).inserted}
                guard !hasMain else {return false};hasMain=true;return true
            }
            let main = result.pets.first(where:{$0.profileID == nil}) ?? PetPlacement()
            if !hasMain {result.pets.insert(main,at:0)}
            if result.pets.count>4 {
                result.pets = Array(result.pets.prefix(4))
                if !result.pets.contains(where:{$0.profileID == nil}) {result.pets[3]=main}
            }
            return result
        } catch {
            let backup = root.appendingPathComponent("settings-damaged-\(Int(Date().timeIntervalSince1970)).json")
            try? FileManager.default.copyItem(at:state,to:backup)
            log("设置读取失败，已使用默认设置：\(error.localizedDescription)")
            return AppState()
        }
    }
    static func save(_ state: AppState) throws {
        try prepare()
        let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted,.sortedKeys]
        try encoder.encode(state).write(to:Self.state, options:.atomic)
    }
    static func log(_ message: String) {
        try? prepare()
        let url = root.appendingPathComponent("error.log")
        let data = Data("\(ISO8601DateFormatter().string(from:Date())) \(message)\n".utf8)
        if let h = try? FileHandle(forWritingTo:url) { defer {try? h.close()}; _ = try? h.seekToEnd(); try? h.write(contentsOf:data) }
        else { try? data.write(to:url) }
    }
}
