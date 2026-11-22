# Phase 9 — 原生 Glass 与 UI 精修

用户于 2026-11-22 批准执行。版本为 0.9.0 / build 12，最低部署 iOS 18.0。

## 界面

- iOS 26 的导航栏、Tab 和快速录入 Sheet 使用系统材质。「记一笔」位于账单页底部，在 iOS 26 使用原生 Liquid Glass。iOS 18 回退到 `ultraThinMaterial`。降低透明度和增强对比度使用不透明背景。 [Apple Liquid Glass](https://developer.apple.com/documentation/SwiftUI/Applying-Liquid-Glass-to-custom-views)
- 浅色和深色各有适配的强调色，App 图标统一使用用户提供的白龙女孩与钱包插画。内置图标沿用 SF Symbols，选择器显示可朗读的中文名称。账单的 emoji 与用户图片继续展示。
- 大字体下金额和值分行，分段选择器改用系统菜单。VoiceOver 可读出账单的方向、原金额及币种、分类和账户。快速录入关闭后，VoiceOver 焦点回到「记一笔」。
- 保存账单、模板一键记账、删除和恢复成功后有触觉反馈。列表变更使用短动画，降低动态效果时停用应用层动画。

## 自动验证

- 2026-11-22，Xcode 26.3 使用源码 `6c7dbbc` 完成模拟器构建、119 项 Swift 测试、iOS 26.2 模拟器的 10 项 UI 测试及未签名设备 Archive。iOS 18.6 模拟器复跑普通字号导航及深色最大辅助字号录入，两项均通过。降低透明度、增强对比度和减少动态效果的策略由 Swift 测试覆盖。 [CI](https://github.com/loliruru/cost-ios/actions/runs/44995838406) [测试日志](https://github.com/loliruru/cost-ios/actions/runs/44995838406/artifacts/14744607457)
- iOS 26 首轮 UI 测试发现详情的编辑按钮会落到首屏外，周期删除确认会生成同名的嵌套无障碍节点。编辑入口移至工具栏，删除确认测试按稳定标识定位，复跑通过。 [首轮日志](https://github.com/loliruru/cost-ios/actions/runs/44994093602)
- 在 Windows 下载复核了最低支持 iOS 18.0 的未签名 arm64 IPA。主图标指向白龙女孩插画的 AppIcon 资源，包内有编译后的资产目录和图标文件。IPA 共 5,321,095 字节，SHA-256 为 `ee30e9060cfab4536c0d9ad024bdbaf0d142f7968159c7b36609de4dabd93621`，与 CI 一致。 [未签名 IPA](https://github.com/loliruru/cost-ios/actions/runs/44995838406/artifacts/14744183398)

## 真机验收

待用户确认真机材质、布局、动效、触觉和 VoiceOver 流程。

1. 在 iOS 26 用测试账目切换账单、模板、统计和设置。检查两种外观下的 App 图标、导航和底部操作。滚动账单时核对文字和金额的对比度。
2. 打开「记一笔」，展开详情、输入金额并在键盘打开时保存。用最大辅助字号复测，核对收支菜单、分类、冻结金额和关闭、保存按钮。关闭草稿后再打开并确认内容保留。
3. 在 iPhone 的「设置 → 辅助功能 → 显示与文字大小」中分别打开「降低透明度」「增强对比度」。在「设置 → 辅助功能 → 动态效果」打开「减弱动态效果」。部分系统版本将「辅助功能」显示为「无障碍」。回到 Cost 核对控制层材质及开合，再用旁白从新增走到保存，打开详情、删除和撤销，核对按钮名称、金额币种和 Sheet 关闭后的焦点。 [Apple 显示设置](https://support.apple.com/zh-cn/111773) [Apple 动态效果设置](https://support.apple.com/en-cn/guide/iphone/iph0b691d3ed/ios)
4. 核对保存、删除和恢复的触觉。若有问题，记录 iOS 版本、显示或辅助功能设置及出现问题的页面。
5. 在 USD 本位下输入 15 并关闭草稿，重新打开 App，确认草稿仍是 15 USD。切到 CNY 本位后打开「记一笔」，确认使用 CNY，输入金额即可同币种保存。切回 USD 后确认能继续原来的草稿。
