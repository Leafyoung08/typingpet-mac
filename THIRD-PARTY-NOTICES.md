# 第三方来源说明

## Typing Pet 与角色图片

- 原项目：[Typing Pet](https://github.com/swoonqx/TypingPet)
- 原作者／公开账号：`swoonqx`（原 Windows 程序的签名发布者名称在说明中记为 `snoonqx`）
- 用户提供版本：TypingPet v4.3.1
- 参考文档提交：`fbb59d430176d9d34bce3e8af04b4499e83a1640`
- 沿用文件：`Resources/images/basic.png`、`left.png`、`right.png`、`pattern1.png`、`pattern2.png`
- 应用图标由 `basic.png` 居中留白、缩放生成。

本项目根据公开说明独立实现 macOS 原生行为，没有使用 Windows 程序源码；用户提供的 ZIP 与原项目当前公开仓库只包含说明文档。原 Windows EXE 不包含在 Mac 应用中，也不参与运行。

原 README 的“使用范围”允许个人用途或为个人使用环境修改程序，并请求介绍、分享时附官方 GitHub 链接。提供的材料未包含一般性开源许可证。本次交付针对用户个人使用，不声明获得了原程序或角色素材的公开再分发、商业授权。对外发布前请与原作者确认适用许可。

Typing Pet 名称、角色图片及其他原始素材的权利归其相应权利人所有。本 macOS 版本非原作者的官方发布。

## Apple 系统框架

应用调用 macOS 提供的 AppKit、SwiftUI、ImageIO、ApplicationServices 和 ServiceManagement 等系统框架。随系统框架本身不复制到交付包。
