# typingpet-mac

（默认版本为阿蒲oc）让桌面小宠物跟着打字交替抬手、轻轻弹跳。内置本项目使用者提供的三张默认状态图，使用原生 macOS 窗口与中文设置界面，支持自定义角色、按键动作和多宠物。

这是根据 [swoonqx/TypingPet](https://github.com/swoonqx/TypingPet) 公开功能说明独立实现的非官方 Mac 版，保留原版本的两张模式图片。默认三张基础状态图由本项目使用者提供，权利归相应权利人。原项目与素材来源见 [THIRD-PARTY-NOTICES.md](THIRD-PARTY-NOTICES.md)。

## 下载与安装

适用于 **macOS 13 或更新版本**，发布包为 **Apple 芯片 / Intel 通用应用**。

[下载 v1.0.0 通用版](https://github.com/yangjieyu6226/typingpet-mac/releases/download/v1.0.0/typingpet-mac-v1.0.0-universal.zip) · [查看最新版本](https://github.com/yangjieyu6226/typingpet-mac/releases/latest)

1. 下载并解压 `typingpet-mac-v1.0.0-universal.zip`。
2. 将 `Typing Pet.app` 拖入“应用程序”文件夹，再打开。
3. 在“系统设置 → 隐私与安全性 → 输入监控”中允许 Typing Pet。系统若要求重新打开，请退出应用后再启动。
4. 在其他应用中打字，查看宠物动作。尚未授权时，也可以在设置里点击“预览动作”。

2026-10-25 已直接替换既有 v1.0.0 下载包中的默认三张图片及应用图标，版本和下载地址保持不变。新安装会显示新的默认角色；已有用户替换应用后，自定义图片与设置继续保留，在“图片与按键”中恢复默认即可使用新的内置状态图。引用内置基础图的预设也会显示对应的新图。

当前发布包使用本地临时签名（ad-hoc），没有 Developer ID 签名或 Apple 公证。若首次打开被系统阻止，可按“系统设置 → 隐私与安全性”中提供的提示打开。

## 功能

- 普通按键交替显示左手与右手姿势，可调整宠物大小、跳动幅度与透明度。
- 自定义默认、左手、右手图片，以及指定按键、组合键或鼠标按钮的动作图片；最多 20 个按键模式。
- 支持 PNG、JPG、GIF、APNG；每张图片最多 15 MB、300 帧。
- 保存最多 10 个预设，导入与导出 `.typingpet` 文件，方便分享角色。
- 同时显示最多 4 只宠物，支持拖动、置顶、层级调整、悬停淡化和位置锁定。
- 菜单栏设置、暂停动作、登录时自动启动；设置与位置自动保存。

右键宠物或点击菜单栏图标可打开菜单。锁定位置后，鼠标会穿过宠物；请通过菜单栏图标解锁。启用登录时自动启动前，请先将应用放入“应用程序”文件夹，并按 macOS 提示允许登录项。

## 自绘角色与预设

建议将默认、左手、右手图片画在相同尺寸和位置的透明画布上。当前内置的三张基础状态图均为 1374 × 1374 像素。

在“图片与按键”中换图并设置动作，然后在“预设”中保存、导出 `.typingpet` 文件。导出会包含该预设引用的自定义图片；内置图片保留为引用。若分享的预设需要全部使用自己的绘画，请替换三张基础状态图和所有保留的模式图片。

`.typingpet` 是本 Mac 版的独立格式，**不兼容 Windows 版 ZIP 预设或配置**，需要接收者使用本 Mac 版导入。

## 隐私与数据

应用离线运行，输入事件仅用于即时切换动作，不保存输入的文字或按键历史，不上传输入数据。设置、自定义图片与错误记录位于：

```text
~/Library/Application Support/TypingPetMac/
```

密码等安全输入场景、受系统保护的界面，或部分全屏程序，可能限制全局输入监听与桌面叠加显示。

## 从源码构建

需要 macOS 与 Xcode Command Line Tools：

```sh
xcode-select --install
git clone https://github.com/yangjieyu6226/typingpet-mac typingpet-mac
cd typingpet-mac
./build.sh
```

默认生成并校验 `arm64` / `x86_64` 通用程序，输出为：

```text
dist/Typing Pet.app
dist/TypingPet-macOS.zip
```

只构建当前机器架构可运行 `TYPINGPET_NATIVE_ONLY=1 ./build.sh`。构建使用 Swift 5 模式和系统框架，不需要第三方运行时；临时签名不使用 Developer ID 或在线公证服务。

构建后执行自动检查：

```sh
Tests/run.sh
```

2026-10-21 的本地验证包含 75 项自动检查，以及通过 Rosetta 执行的 22 项 Intel 主程序自测。系统权限仍需使用者亲自授权；完整范围见 [VALIDATION.md](VALIDATION.md)。

更多操作说明见 [README-使用说明.md](README-使用说明.md)，版本说明见 [RELEASE_NOTES.md](RELEASE_NOTES.md)。
