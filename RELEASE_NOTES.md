# v1.0.0

Typing Pet 非官方 macOS 原生版的首次发布，根据 [swoonqx/TypingPet](https://github.com/swoonqx/TypingPet) 的公开功能说明独立实现，保留原随附角色图片与来源说明。

## 下载

- 文件：`typingpet-mac-v1.0.0-universal.zip`
- 系统：macOS 13 或更新版本
- 架构：Apple 芯片（arm64）与 Intel（x86_64）通用应用
- [下载此版本](https://github.com/yangjieyu6226/typingpet-mac/releases/download/v1.0.0/typingpet-mac-v1.0.0-universal.zip) · [最新发布](https://github.com/yangjieyu6226/typingpet-mac/releases/latest)

解压后将 `Typing Pet.app` 放入“应用程序”文件夹。要在其他应用中打字时触发动作，请在“隐私与安全性 → 输入监控”中授权；系统如有提示，请退出后重新打开。

## 功能

- 交替抬手与弹跳动作，自定义 PNG / JPG / GIF / APNG 图片。
- 最多 20 个按键、组合键或鼠标动作模式，10 个预设，同时显示 4 只宠物。
- `.typingpet` 预设导入／导出，原生中文设置与菜单栏控制。
- 拖动位置、置顶、层级、透明度、悬停淡化、位置锁定与登录时自动启动。
- 离线运行，不记录文字或按键历史，不上传输入数据。

## 验证与兼容范围

2026-10-21 在 Apple 芯片、macOS 15.3.1 环境完成 75 项自动检查（22 项主程序、53 项图片专项）；x86_64 主程序通过 Rosetta 重复执行 22 项自测并通过。已检查通用二进制与临时签名，并打开检查四页设置；具体记录见 [VALIDATION.md](VALIDATION.md)。

当前包采用 ad-hoc 临时签名，未使用 Developer ID 签名或 Apple 公证。输入监控授权需要使用者完成；重新登录后的自动启动未做实际验证。`.typingpet` 为本版格式，不兼容 Windows ZIP 预设。

原项目与角色图片来源见 [THIRD-PARTY-NOTICES.md](THIRD-PARTY-NOTICES.md)。
