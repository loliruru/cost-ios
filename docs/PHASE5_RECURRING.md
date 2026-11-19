# Phase 5 周期记账

「设置 → 周期记账」可新增、编辑、暂停、恢复和删除法币规则。六种频率覆盖每天、工作日、指定星期、每月、每年和 N 日/周/月/年。起止日期包含当天，计划时间及业务日按规则时区计算。月底可取末日或跳过；恢复时选择补记或跳过过去业务日。编辑后的计划从当前业务日重新计算，保留已经生成的账单与执行结果。

沿用 v1 规则、标签和执行表。`recurring:<ruleID>:<scheduledAt>` 请求键与执行表唯一键共同防重；账单、标签、执行状态和游标一次提交。到期失败会显示在待处理列表，可重试或确认跳过。等待估值的规则不会阻塞其他规则。外币 latest 和 historical 路径使用固定 Provider 测试；当前生产版缺少在线估值时保留待处理记录。删除规则清理其执行状态，历史账单和来源 ID 保留。

前台激活会处理到期批次；系统后台刷新使用同一执行入口，取消时保留已提交账单并从剩余游标继续。用户可显式开启本地通知，预排最近 32 个未来提醒，暂停或删除会撤销对应提醒。通知只显示通用文案，后台时间由系统决定。 [Apple 后台任务说明](https://developer.apple.com/documentation/SwiftUI/Scene/backgroundTask%28_%3Aaction%3A%29) · [本地通知 API](https://developer.apple.com/documentation/UserNotifications/UNUserNotificationCenter)

## 真机试用

1. 新增一条起始日为今天、当地时间已过的本币规则。打开账单页确认只生成一笔，发生时间为计划时间。切到后台再打开，确认没有重复。
2. 暂停规则再恢复，分别检查两种补记策略。删除规则后核对已生成的账单仍在。
3. 开启到期提醒并授权，新增一条几分钟后到期的规则，把 Cost 切到后台。核对通用通知，再打开 Cost 确认账单。核对暂停或删除后该规则的后续提醒已取消。设备何时执行系统后台刷新由 iOS 决定。
4. 在浅色、深色和大字体下查看规则编辑和待处理列表，确认日期、时区、补记和操作标签清晰。

## 验证状态

2026-11-19，应用提交 `abff21fc85c202cd36969f7ee307f08ce84dc330` 在 Xcode 16.4、Swift 6.1.2、iOS 18.5 SDK 下通过 Simulator Build、83 项 Swift 测试、5 项 UI 测试及设备 Archive。 [CI run 44541018112](https://github.com/loliruru/cost-ios/actions/runs/44541018112)

- Swift 测试覆盖 Android 的 gap/overlap、半小时 DST、月末和闰年、两种补记、取消、数据库重开、并发防重、写入回滚、外币估值重试和跳过。前台与后台入口使用同一账本，测试同时核对后台刷新标识符和模式。UI 测试验证设置入口、到期生成和删除规则后的账单保留。
- Windows 下载后复核 IPA 为 0.5.0 / build 6，未签名 arm64 iOS，最低 iOS 18.0，共 2,100,396 bytes。SHA-256 为 `c0ef14cbe38dd7df9c6571ac26c7c73b87a6a45987cc0269aa3b046e6ad68957`，与 CI 一致。包内后台标识符为 `com.personal.cost.recurring-refresh`，模式为 `fetch`。 [未签名 IPA](https://github.com/loliruru/cost-ios/actions/runs/44541018112/artifacts/14540190101) · [构建与测试证据](https://github.com/loliruru/cost-ios/actions/runs/44541018112/artifacts/14537809772)
- Foundation、schema、6 项 IPA 校验器测试和 Android 53 文件只读基线核对通过。此前 CI 揭示了 UserNotifications 的 Swift 6 actor 隔离和测试宏的 `try` 展开问题，修复后重跑通过。排队时使用的 Intel 验证分支包含 runner 配置差异，最终验收使用主分支的标准 macOS runner。
- 真机通知、系统后台实际调度及主观视觉待用户验收。
