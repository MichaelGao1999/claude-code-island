# Claude Code Island — 功能需求文档

> 版本：1.0 | 更新时间：2026-06-22

---

## 一、项目概述

Claude Code Island 是一个跨设备 Agent HUD 系统，为 Claude Code 提供实时状态监控和远程审批功能。

**目标用户：**
- 使用 Claude Code 进行开发工作的开发者
- 需要远程监控 Claude Code 执行状态的用户
- 对高风险操作需要审批确认的场景

---

## 二、功能列表

### 2.1 核心功能

| 功能 | 优先级 | 平台 | 说明 |
|------|--------|------|------|
| 实时状态显示 | P0 | macOS/iOS | 显示 Claude Code 当前任务状态 |
| 进度监控 | P0 | macOS/iOS | 显示任务完成百分比 |
| 审批系统 | P0 | macOS/iOS | 高危操作前暂停等待确认 |
| Live Activity | P1 | iOS | 锁屏实时状态显示 |
| 事件历史 | P1 | macOS/iOS | 查看最近事件记录 |
| Mock 模式 | P1 | macOS/iOS | 无需服务器测试功能 |

### 2.2 macOS 功能

| 功能 | 说明 |
|------|------|
| MenuBarExtra | 菜单栏/灵动岛显示状态 |
| Compact/Expanded 模式 | 点击展开详细信息 |
| 审批弹窗 | 显示命令摘要、风险等级、Approve/Reject 按钮 |
| 键盘快捷键 | Enter=批准, Esc=拒绝, I=检查详情 |
| 设置窗口 | 配置服务器地址、自动连接、通知 |

### 2.3 iOS 功能

| 功能 | 说明 |
|------|------|
| WebSocket Bridge | 连接 Mac relay 接收事件 |
| Live Activity | 锁屏显示当前任务、状态、进度 |
| 远程审批 | 在 iPhone 上审批 Mac 上的操作 |
| 事件列表 | 查看最近事件历史 |

---

## 三、用户故事

### 3.1 实时监控

**场景：** 用户在 Mac 上运行 Claude Code，同时在 iPhone 上查看状态。

```
用户故事 #1：
作为 开发者
我想要 在 iPhone 上实时看到 Claude Code 的执行状态
以便于 不打开终端也能了解进度
```

**验收标准：**
- ✅ iOS App 显示当前任务描述
- ✅ 进度条实时更新
- ✅ Live Activity 在锁屏显示状态

### 3.2 远程审批

**场景：** Claude Code 执行高风险操作（如删除文件），需要用户确认。

```
用户故事 #2：
作为 开发者
我想要 在 iPhone 上审批 Claude Code 的高风险操作
以便于 不在 Mac 前也能控制执行
```

**验收标准：**
- ✅ 收到审批请求时显示通知
- ✅ 审批界面显示命令摘要和风险等级
- ✅ Approve/Reject 按钮可用
- ✅ 审批结果实时发送到 Mac

### 3.3 菜单栏监控

**场景：** 用户在 Mac 上工作，通过菜单栏查看 Claude Code 状态。

```
用户故事 #3：
作为 开发者
我想要 在 Mac 菜单栏看到 Claude Code 的状态
以便于 不切换窗口也能监控
```

**验收标准：**
- ✅ MenuBarExtra 显示状态图标
- ✅ 点击展开详细信息
- ✅ 审批弹窗可交互

---

## 四、MVP 范围

### 4.1 MVP 包含

- ✅ macOS 菜单栏 App（MenuBarExtra）
- ✅ iOS 伴侣 App（Live Activity + 远程审批）
- ✅ WebSocket 通信协议定义
- ✅ 事件 JSON Schema（9 种事件类型）
- ✅ Mock 模式测试

### 4.2 MVP 不包含

- ❌ 真实 WebSocket 服务器实现
- ❌ iOS 真机部署和代码签名
- ❌ APNS 推送通知
- ❌ 安全签名验证（HMAC）
- ❌ 单元测试

---

## 五、约束条件

### 5.1 技术约束

- Swift 5.9+ / SwiftUI
- macOS 13+（MenuBarExtra）
- iOS 16.1+（Live Activity）
- 零第三方依赖

### 5.2 设计约束

- 不修改 macOS 系统文件
- 不处理 iOS 代码签名
- 不实现真实 Claude Code WebSocket 服务器

---

## 六、质量标准

### 6.1 代码质量

- ✅ 全部 Swift 文件语法验证通过
- ✅ 使用 MARK 注释分区
- ✅ 文档注释覆盖公共 API

### 6.2 UI 质量

- ✅ SwiftUI 原生组件
- ✅ 响应式布局
- ✅ 深色模式兼容

---

## 七、验收清单

| 项目 | 状态 |
|------|------|
| macOS App 可构建 | ✅ |
| iOS App 可构建 | ✅ |
| Mock 模式可用 | ✅ |
| 事件协议完整 | ✅ |
| 文档齐全 | ✅ |