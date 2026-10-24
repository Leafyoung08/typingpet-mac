import AppKit
import SwiftUI

final class SettingsWindowController: NSWindowController {
    init(controller: AppController) {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 740, height: 620),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "TypingPet 设置"
        window.minSize = NSSize(width: 660, height: 560)
        window.isReleasedWhenClosed = false
        window.contentView = NSHostingView(rootView: TypingPetSettingsView(controller: controller))
        super.init(window: window)
        window.center()
        window.setFrameAutosaveName("TypingPetSettingsWindow")
    }

    required init?(coder: NSCoder) { nil }

    func present() {
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }
}

private struct TypingPetSettingsView: View {
    @ObservedObject var controller: AppController
    @State private var selectedTab = min(3, max(0, Int(ProcessInfo.processInfo.environment["TYPINGPET_SETTINGS_TAB"] ?? "0") ?? 0))
    @State private var presetName = ""
    @State private var renamingPresetID: UUID?
    @State private var renamedPresetName = ""
    @State private var isRenaming = false

    private let imageRoles: [(id: String, title: String, detail: String)] = [
        ("basic", "默认状态", "没有按键时显示"),
        ("left", "左手抬起", "普通按键时与另一只手交替显示"),
        ("right", "右手抬起", "普通按键时与另一只手交替显示")
    ]

    var body: some View {
        VStack(spacing: 0) {
            TabView(selection: $selectedTab) {
                generalTab.tabItem { Label("常规", systemImage: "gearshape") }.tag(0)
                imagesTab.tabItem { Label("图片与按键", systemImage: "photo") }.tag(1)
                presetsTab.tabItem { Label("预设", systemImage: "square.stack") }.tag(2)
                layersTab.tabItem { Label("图层", systemImage: "square.3.layers.3d") }.tag(3)
            }
            .padding(.horizontal, 14)
            .padding(.top, 14)

            Divider()
            HStack {
                Button("打开数据文件夹", action: controller.showDataFolder)
                    .help("查看保存的设置、预设图片和错误日志")
                Spacer()
                Button("预览动作", action: controller.preview)
                    .help("演示按键动作，无需输入监控权限")
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
        }
        .frame(minWidth: 640, minHeight: 520)
        .onAppear(perform: controller.refreshPermission)
        .sheet(isPresented: $isRenaming) { renameSheet }
    }

    private var generalTab: some View {
        settingsScroll {
            section("输入监控权限") {
                HStack(alignment: .top, spacing: 10) {
                    Image(systemName: controller.permissionGranted ? "checkmark.circle.fill" : "hand.raised")
                        .foregroundColor(controller.permissionGranted ? Color(nsColor: .systemGreen) : .secondary)
                        .font(.title2)
                        .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 5) {
                        Text(controller.permissionGranted ? "已允许输入监控" : "允许后，宠物会跟随键盘和鼠标动作")
                            .fontWeight(.medium)
                        Text("仅在本机监听按键与鼠标按下事件，用于切换宠物图片；不会记录或上传输入内容。")
                            .foregroundColor(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                HStack {
                    if !controller.permissionGranted {
                        Button("请求权限", action: controller.requestInputPermission)
                    }
                    Button("打开系统设置", action: controller.openPrivacySettings)
                    Button("重新检查", action: controller.refreshPermission)
                }
                if !controller.permissionGranted {
                    helpText("在「隐私与安全性 → 输入监控」中启用 TypingPet，然后重新检查。系统如提示重新打开，请退出后再次启动。可随时点击底部「预览动作」试用。")
                }
            }

            section("外观") {
                valueSlider("宠物宽度", value: setting(\.size), range: 120...800, step: 10,
                            display: "\(Int(controller.state.settings.size)) 像素")
                valueSlider("跳动幅度", value: setting(\.bounce), range: 0...18, step: 1,
                            display: controller.state.settings.bounce == 0 ? "关闭" : "\(Int(controller.state.settings.bounce)) 像素")
                valueSlider("不透明度", value: setting(\.opacity), range: 0.15...1, step: 0.05,
                            display: "\(Int((controller.state.settings.opacity * 100).rounded()))%")
            }

            section("行为") {
                Toggle("保持在其他窗口上方", isOn: setting(\.alwaysOnTop))
                Toggle("锁定位置并让鼠标点击穿透", isOn: setting(\.locked))
                helpText("取消锁定后，可拖动宠物调整位置。点击穿透开启时，鼠标会直接操作后面的窗口。")
                Toggle("鼠标悬停时淡出", isOn: setting(\.fadeOnHover))
                Toggle("暂停按键动作", isOn: setting(\.paused))
                Toggle("登录时自动启动", isOn: Binding(get: { controller.launchAtLogin }, set: controller.setLogin))
                HStack {
                    Button("重置宠物位置", action: controller.resetPositions)
                    Spacer()
                }
                .padding(.top, 3)
            }
        }
    }

    private var imagesTab: some View {
        settingsScroll {
            section("主宠物图片") {
                helpText("支持 PNG、JPG、GIF 和 APNG；透明背景的图片效果更好。每个文件最多 15 MB、300 帧；动图解码受内存上限保护。")
                ForEach(imageRoles, id: \.id) { role in
                    HStack(spacing: 12) {
                        PetThumbnail(name: controller.state.current.images[role.id] ?? role.id, side: 58)
                        VStack(alignment: .leading, spacing: 4) {
                            Text(role.title).fontWeight(.medium)
                            Text(role.detail).font(.callout).foregroundColor(.secondary)
                            imageFileLabel(controller.state.current.images[role.id] ?? role.id)
                        }
                        Spacer(minLength: 8)
                        Button("选择图片…") { controller.chooseImage(role: role.id) }
                        Button("恢复默认") { controller.resetImage(role: role.id) }
                            .disabled((controller.state.current.images[role.id] ?? role.id) == role.id)
                    }
                    .padding(.vertical, 4)
                    if role.id != "right" { Divider() }
                }
            }

            section("指定按键图片") {
                HStack(alignment: .firstTextBaseline) {
                    Text("为特定按键或鼠标键显示单独的图片。")
                        .foregroundColor(.secondary)
                    Spacer()
                    Text("\(controller.state.current.patterns.count) / 20")
                        .monospacedDigit()
                        .foregroundColor(.secondary)
                    Button("添加按键", action: controller.addPattern)
                        .disabled(controller.state.current.patterns.count >= 20)
                }
                helpText("点击「录制按键」后按下目标键或组合键。录制鼠标键需先允许输入监控，并在设置窗口外点击。按 Esc 取消录制。")
                if controller.state.current.patterns.isEmpty {
                    Text("尚未添加指定按键。普通按键会交替显示上方的左手与右手图片。")
                        .foregroundColor(.secondary)
                        .padding(.vertical, 10)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                ForEach(controller.state.current.patterns) { pattern in
                    patternRow(pattern)
                    if pattern.id != controller.state.current.patterns.last?.id { Divider() }
                }
            }
        }
    }

    private func patternRow(_ pattern: PetPattern) -> some View {
        let isCapturing = controller.capturePatternID == pattern.id
        return VStack(alignment: .leading, spacing: 7) {
            HStack(spacing: 12) {
                PetThumbnail(name: pattern.image, side: 48)
                VStack(alignment: .leading, spacing: 4) {
                    Text(isCapturing ? "等待输入…" : pattern.trigger.label)
                        .fontWeight(.medium)
                        .foregroundColor(isCapturing ? Color.accentColor : Color.primary)
                    imageFileLabel(pattern.image)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                if isCapturing {
                    Button("取消", action: controller.cancelCapture)
                } else {
                    Button("录制按键") { controller.recordPattern(id: pattern.id) }
                }
                Button("选择图片…") { controller.choosePatternImage(id: pattern.id) }
                Button {
                    controller.removePattern(id: pattern.id)
                } label: {
                    Image(systemName: "trash")
                }
                .help("删除此按键图片")
                .accessibilityLabel("删除 \(pattern.trigger.label) 的图片规则")
            }
            if isCapturing {
                Text(controller.permissionGranted
                     ? "现在按下目标键，或在设置窗口外点击鼠标；松开修饰键可单独录制该键。"
                     : "现在在此窗口内按下目标键；全局响应需先允许输入监控。")
                    .font(.callout)
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.vertical, 4)
    }

    private var presetsTab: some View {
        settingsScroll {
            section("保存当前宠物") {
                helpText("预设保存主宠物的三张状态图片和指定按键图片。尺寸、透明度等常规设置由所有宠物共用。")
                HStack {
                    TextField("预设名称（最多 16 个字符）", text: $presetName)
                        .textFieldStyle(.roundedBorder)
                        .onChange(of: presetName) { presetName = String($0.prefix(16)) }
                        .onSubmit(saveCurrentPreset)
                    Button(isOverwritingPreset ? "覆盖保存" : "保存预设", action: saveCurrentPreset)
                        .disabled(!canSavePreset)
                }
                HStack {
                    Text("\(controller.state.presets.count) / 10 个预设")
                        .foregroundColor(.secondary)
                    Spacer()
                    Button("导入预设…", action: controller.importPreset)
                        .disabled(controller.state.presets.count >= 10)
                }
                if controller.state.presets.count >= 10 {
                    helpText("预设已满。可使用已有名称覆盖保存，或删除一个预设后再保存、导入。")
                }
                helpText("导入和导出使用 Mac 版 .typingpet 格式，暂不兼容 Windows 版 ZIP 预设。")
            }

            section("已保存的预设") {
                if controller.state.presets.isEmpty {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("还没有预设").fontWeight(.medium)
                        Text("设置好图片与按键后，为当前宠物取个名字并保存；也可以导入已有预设。")
                            .foregroundColor(.secondary)
                    }
                    .padding(.vertical, 10)
                }
                ForEach(controller.state.presets) { preset in
                    presetRow(preset)
                    if preset.id != controller.state.presets.last?.id { Divider() }
                }
                if !controller.state.presets.isEmpty {
                    helpText("「应用到主宠物」后可继续编辑图片与按键。更改不会自动写回原预设，请以同名覆盖保存或另存为新预设。最多同时显示 4 只宠物，包含主宠物。")
                }
            }
        }
    }

    private func presetRow(_ preset: PetProfile) -> some View {
        let visible = controller.state.pets.contains { $0.profileID == preset.id }
        return HStack(spacing: 12) {
            PetThumbnail(name: preset.images["basic"] ?? "basic", side: 52)
            VStack(alignment: .leading, spacing: 5) {
                Text(preset.name).fontWeight(.medium).lineLimit(2)
                Text("\(preset.patterns.count) 个指定按键\(visible ? " · 已显示额外宠物" : "")")
                    .font(.callout)
                    .foregroundColor(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            Button("应用到主宠物") { controller.applyPreset(id: preset.id) }
            Button(visible ? "隐藏宠物" : "显示宠物") { controller.togglePet(profileID: preset.id) }
                .disabled(!visible && controller.state.pets.count >= 4)
                .help(!visible && controller.state.pets.count >= 4 ? "最多同时显示 4 只宠物，请先隐藏一只" : "独立显示或隐藏此预设的宠物")
            Menu {
                Button("重命名…") {
                    renamingPresetID = preset.id
                    renamedPresetName = preset.name
                    isRenaming = true
                }
                Button("导出预设…") { controller.exportPreset(id: preset.id) }
                Divider()
                Button("删除预设…", role: .destructive) {
                    controller.deletePreset(id: preset.id)
                }
            } label: {
                Image(systemName: "ellipsis")
                    .accessibilityLabel("\(preset.name) 的更多操作")
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
        }
        .padding(.vertical, 5)
    }

    private var layersTab: some View {
        settingsScroll {
            section("宠物前后顺序") {
                helpText("列表顶部的宠物位于最前方。使用箭头调整重叠顺序；取消「常规」中的位置锁定后，可在桌面拖动宠物。")
                HStack {
                    Text("\(controller.state.pets.count) / 4 只宠物")
                        .foregroundColor(.secondary)
                    Spacer()
                    Button("重置所有位置", action: controller.resetPositions)
                }
                ForEach(Array(controller.state.pets.enumerated()), id: \.element.id) { index, placement in
                    layerRow(placement, index: index)
                    if index < controller.state.pets.count - 1 { Divider() }
                }
            }
            helpText("在「预设」中点击「显示宠物」，可添加额外宠物。所有宠物共用尺寸、跳动幅度和透明度；最多显示 4 只，以控制动画的内存占用。")
        }
    }

    private func layerRow(_ placement: PetPlacement, index: Int) -> some View {
        let profile = placement.profileID.flatMap { id in controller.state.presets.first { $0.id == id } } ?? controller.state.current
        let isMain = placement.profileID == nil
        return HStack(spacing: 12) {
            PetThumbnail(name: profile.images["basic"] ?? "basic", side: 50)
            VStack(alignment: .leading, spacing: 4) {
                Text(isMain ? "主宠物" : profile.name).fontWeight(.medium).lineLimit(2)
                Text(index == 0 ? "最前方" : "第 \(index + 1) 层")
                    .font(.callout)
                    .foregroundColor(.secondary)
            }
            Spacer(minLength: 8)
            if let profileID = placement.profileID {
                Button("隐藏") { controller.togglePet(profileID: profileID) }
            }
            Button {
                controller.moveLayer(id: placement.id, delta: -1)
            } label: {
                Image(systemName: "chevron.up")
            }
            .disabled(index == 0)
            .help("移到前一层")
            .accessibilityLabel("将\(isMain ? "主宠物" : profile.name)移到前一层")
            Button {
                controller.moveLayer(id: placement.id, delta: 1)
            } label: {
                Image(systemName: "chevron.down")
            }
            .disabled(index == controller.state.pets.count - 1)
            .help("移到后一层")
            .accessibilityLabel("将\(isMain ? "主宠物" : profile.name)移到后一层")
        }
        .padding(.vertical, 5)
    }

    private var renameSheet: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("重命名预设").font(.headline)
            TextField("预设名称", text: $renamedPresetName)
                .textFieldStyle(.roundedBorder)
                .onChange(of: renamedPresetName) { renamedPresetName = String($0.prefix(16)) }
                .onSubmit(finishRename)
            HStack {
                Spacer()
                Button("取消") { isRenaming = false }
                    .keyboardShortcut(.cancelAction)
                Button("保存", action: finishRename)
                    .keyboardShortcut(.defaultAction)
                    .disabled(renamedPresetName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(24)
        .frame(width: 360)
    }

    private var trimmedPresetName: String {
        String(presetName.trimmingCharacters(in: .whitespacesAndNewlines).prefix(16))
    }

    private var isOverwritingPreset: Bool {
        controller.state.presets.contains { $0.name == trimmedPresetName }
    }

    private var canSavePreset: Bool {
        !trimmedPresetName.isEmpty && (controller.state.presets.count < 10 || isOverwritingPreset)
    }

    private func saveCurrentPreset() {
        guard canSavePreset else { return }
        let name = trimmedPresetName
        let wasOverwrite = isOverwritingPreset
        controller.savePreset(name: trimmedPresetName)
        if !wasOverwrite && controller.state.presets.contains(where: { $0.name == name }) {
            presetName = ""
        }
    }

    private func finishRename() {
        let name = renamedPresetName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let id = renamingPresetID, !name.isEmpty else { return }
        controller.renamePreset(id: id, name: name)
        isRenaming = false
    }

    private func setting<Value>(_ keyPath: WritableKeyPath<PetSettings, Value>) -> Binding<Value> {
        Binding(
            get: { controller.state.settings[keyPath: keyPath] },
            set: { newValue in controller.edit { $0.settings[keyPath: keyPath] = newValue } }
        )
    }

    private func settingsScroll<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24, content: content)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(20)
        }
    }

    private func section<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title).font(.headline)
            content()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func helpText(_ text: String) -> some View {
        Text(text)
            .font(.callout)
            .foregroundColor(.secondary)
            .fixedSize(horizontal: false, vertical: true)
    }

    private func imageFileLabel(_ name: String) -> some View {
        let builtIn = ["basic", "left", "right", "pattern1", "pattern2"].contains(name)
        return Text(builtIn ? "内置图片" : name)
            .font(.caption)
            .foregroundColor(.secondary)
            .lineLimit(1)
            .truncationMode(.middle)
            .help(builtIn ? "内置图片" : name)
    }

    private func valueSlider(_ title: String, value: Binding<Double>, range: ClosedRange<Double>, step: Double, display: String) -> some View {
        HStack(spacing: 14) {
            Text(title).frame(width: 80, alignment: .leading)
            Slider(value: value, in: range, step: step)
                .accessibilityLabel(title)
                .accessibilityValue(display)
            Text(display)
                .monospacedDigit()
                .frame(width: 80, alignment: .trailing)
        }
    }
}

private struct PetThumbnail: View {
    let name: String
    let side: CGFloat

    var body: some View {
        Group {
            if let image = PetImageLoader.thumbnail(name) {
                Image(nsImage: image).resizable().interpolation(.high).scaledToFit()
            } else {
                Image(systemName: "photo")
                    .font(.title2)
                    .foregroundColor(.secondary)
            }
        }
        .frame(width: side, height: side)
        .accessibilityHidden(true)
    }
}
