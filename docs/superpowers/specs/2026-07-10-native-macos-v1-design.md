# Codex Notch Companion · 原生 macOS V1 设计

> 状态：用户已确认当前视觉，进入实现

## 目标

把已确认的刘海原型落为 macOS 原生常驻应用：顶部贴合主屏幕刘海，非激活状态可见，点击后向下展开为同一块面板。

## 技术与窗口策略

- 使用 SwiftUI 负责视觉，AppKit `NSPanel` 负责无 Dock、非激活、跨 Space 的顶部面板。
- 面板的顶边锚定在 `NSScreen.visibleFrame.maxY`，折叠宽 760、高 72；展开时保持顶边不变，仅向下扩展至 514 高。
- 使用 `.statusBar` 窗口层级与 `.canJoinAllSpaces`、`.fullScreenAuxiliary`、`.stationary` 行为，避免普通窗口切换时消失。
- 折叠/展开与悬停沿用现有视觉：镜像波浪、静态额度线、独立渐变光斑、轻微放大。

## 只读数据边界

- aiusage：读取 `http://127.0.0.1:3847/api/quotas`；成功时更新 5 小时/周额度，失败时保持上次成功值并显示过期状态。
- Local usage：只读 `configured local daily CSV path` 与 `state.json` 的最新条目；不写入、不上传、不重启采集器。
- 第一版每 60 秒刷新一次；手动点击刷新只读取，不执行外部命令。

## 验收

- `xcodegen generate` 后，`xcodebuild ... build` 可通过。
- 纯数据解析单元测试覆盖 aiusage 额度解码与 Local usage CSV 最新记录解析。
- 启动应用会出现折叠刘海；点击展开；按 Esc 收起；无 aiusage 服务时 UI 仍可启动。
