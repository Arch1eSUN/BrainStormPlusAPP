# 长按系统设计 (BrainStorm+ iOS)

> 适用范围：BrainStorm+ iOS 真机版本所有列表 / 卡片 / 气泡。
> 配套实现：`Features/Chat/ChatRoomView.swift`、`Features/Notifications/NotificationListView.swift`、`Features/Tasks/TaskListView.swift`、`Features/Dashboard/DashboardRoleSections.swift`、`Features/OKRs/OKRListView.swift` & `OKRDetailView.swift`、`Features/Deliverables/DeliverableListView.swift`、`Shared/Components/BsWeeklyCadenceStrip.swift`。
> 设计参考：iMessage / Mail.app (iOS 26) / Things 3 / Slack iOS。

---

## 触发方式

- 全部用 **SwiftUI `.contextMenu`** —— 0.5s 长按触发原生菜单（带 preview + 半透明背景 + 系统级缩放动画）。
- 极少数轻量交互（如 `BsWeeklyCadenceStrip` 的 dot peek）继续用 `.onLongPressGesture(minimumDuration:)`，因为它们要展示 **bottom-sheet preview** 而非菜单列表。
- iOS 26 的 `.contextMenu(menuItems:preview:)` 暂未启用 —— 后续可在 chat 气泡接入（preview = enlarged 气泡 + reaction picker），见底部「未来增项」。

## Haptic 规则

- contextMenu 触发时 **iOS 自动给一次 `.rigid` haptic**，**菜单容器层不再叠加任何 Haptic**。
- 菜单**项**点击时按 mutation 类型独立 haptic：
  - 普通 mutation → `Haptic.light()`（标已读 / 复制 / 标完成）
  - 成功完成 → `Haptic.success()`（toggleCompletion → done）
  - 即将进入二次确认 → `Haptic.warning()`（点 destructive 按钮但未真删）
  - destructive 实施 → `Haptic.error()`（confirm 后真正 delete / 撤回）
- swipe action 不再调 Haptic —— 用户反馈"滑动场景过密震动"。

## 菜单结构原则

按从上到下顺序：

1. **顶部：快速反应**
   仅 chat 气泡有 —— 「添加表情」Menu 子项展开 emoji 列表。
2. **中部：mutation 优先于 nav**
   先列「编辑 / 复制 / 标完成 / 修改状态」这种行内副作用，再列「打开详情」「打开来源」这种导航。
3. **`Divider()` 分隔不同语义组**（mutation ↔ destructive 必加 divider；mutation ↔ nav 视情况加）。
4. **底部：destructive**
   `Button(role: .destructive)` —— SwiftUI 自动渲染红色文字。**所有 destructive 必走 `confirmationDialog` 二次确认**，不直接落实。
5. 菜单项数量上限 **5–6 项**（含 submenu 算 1 项）。再多就该改 sheet。

## 文案 / 图标规范

- 每个 `Button` / `NavigationLink` 必须用 `Label("文案", systemImage: "图标")` 形式（保持原生 spacing）。
- 文案中文动词起首：「回复」「复制文本」「标完成」「删除」。
- 图标用 SF Symbols；常用映射：
  - 回复 `arrowshape.turn.up.left` / 转发 `arrowshape.turn.up.right`
  - 复制 `doc.on.doc` / 撤销 `arrow.uturn.backward`
  - 已读 `envelope.open.fill` / 未读 `envelope.badge`
  - 删除 `trash` / 编辑 `pencil` / 修改状态 `slider.horizontal.3`
  - 打开链接 / 跳转 `arrow.up.forward.app`
  - 表情 `face.smiling` / @提及 `at`

## 二次确认（destructive）

- 全部 destructive 走 **`.confirmationDialog`**，而不是 Alert（iOS 26 推荐）。
- dialog 状态用 `@State var pending<Type>: <Type>?` 在 view 顶层维护，**hoist 到 view 根** —— 不要每行单独挂一个 dialog（避免 N 个 binding 互相干扰）。
- dialog 提供 `presenting:` 让 destructive button 闭包直接拿 target；避免在 closure 里再去查找。
- 取消文案统一「取消」，role `.cancel`。

---

## 各位置实施

### 1. Chat 消息气泡 (`ChatRoomView.swift`)

未撤回消息：

| 位置 | 项 | 角色 | 备注 |
|---|---|---|---|
| 顶部 | 添加表情 (Menu → emoji 列表) | 普通 | 触发 `toggleReaction` RPC |
| 中部 | 回复 | 普通 | 设 `replyingTo = msg`，输入栏出现 reply 预览条 |
| 中部 | 复制文本 | 普通 | 仅 `content.isEmpty == false` 时显示；`UIPasteboard` |
| 中部 | @提及此人 | 普通 | 仅别人的消息；`messageText` 前置 `@` + 设 `replyingTo` |
| 中部 | 转发（复制引用） | 普通 | 仅别人的消息；拷贝带 attribution 引用块到剪贴板 |
| 底部 | 撤回 | destructive | 仅 own-message + `canWithdraw(2 min 内)`；走 `chat_withdraw_message` RPC |

**判断 / 注释**：
- "删除" 项不提供 —— `chat_messages` 没有 hard-delete 路径，删除统一走撤回（与 Web 一致）。
- "转发" 暂以剪贴板引用块实现 —— 完整 channel-picker 转发 = 新 sprint 项目。
- "@提及此人" 完整 username 替换需要 profiles 拉取（未来 sprint），当前以 `@` 前缀 + reply lock 完成大半 UX。
- 已撤回消息 → contextMenu 整体不渲染（避免 surface 任何动作）。

### 2. 通知项 (`NotificationListView.swift` + `NotificationListViewModel.swift`)

| 位置 | 项 | 角色 | 备注 |
|---|---|---|---|
| 顶部 | 标为已读 / 标为未读 | 普通 | 互斥单选；按 `isEffectivelyRead` 切换显示 |
| 中部 | 打开来源 | 普通 | 仅 `notification.link` 非空时显示；`Link(destination:)` |
| 底部 | 删除 | destructive | hoisted `confirmationDialog` 二次确认；hard delete |

**判断 / 注释**：
- ViewModel 新增 `markAsUnread` / `delete` 方法（约束允许 —— 不在 Models / Shared）。
- Trailing swipe 也提供"删除"入口（与 contextMenu 共享 `pendingDelete` state）；leading swipe 保留"标已读"原有动作。
- "静音此类" 暂不实施 —— 当前 `AppNotification.NotificationType` 只有 info/success/warning/error，不存在按业务分类（mention / approval / hr）的 enum，"静音此类" 没有有意义的语义粒度，留给未来通知偏好系统。

### 3. 任务行 (`TaskListView.swift`)

| 位置 | 项 | 角色 | 备注 |
|---|---|---|---|
| 顶部 | 标完成 / 撤销完成 | 普通 | 高频动作，永远在最顶 |
| 中部 | 修改状态 (Menu → todo / inProgress / review / done) | 普通 | 当前唯一可改字段，作为「编辑」surrogate |
| 底部 | 删除任务 | destructive | hoisted `confirmationDialog` 二次确认 |

**判断 / 注释**：
- 编辑 sheet 缺失 —— `TaskEditSheet` 还未做；当前以"修改状态"作为 inline 编辑代理。
- swipe action 也走同一 `pendingDeleteTask` state，避免误删（`allowsFullSwipe: false`）。

### 4. 项目行 (`DashboardRoleSections.swift` → `ProjectRowCard`)

| 位置 | 项 | 角色 | 备注 |
|---|---|---|---|
| 顶部 | 打开项目详情 | 普通 | 与 default tap 等价 —— 长按用户也常按习惯走菜单 |
| 中部 | 查看相关任务 | 普通 | 跳到 TaskListView (全量；项目筛选待 sprint) |
| 底部 | 复制项目名 | 普通 | 轻量 share helper |

**判断 / 注释**：
- 没有 destructive 项 —— Dashboard 上的 ProjectRowCard 是 surface，不是 source-of-truth；归档 / 删除属于 ProjectListView/Detail 的职责。
- "编辑项目" 等 ProjectEditSheet 接入后再加。

### 5. Dashboard 卡片 (DashboardWidget 标题长按)

**未实施**。判断：
- 现有 `BsWidgetCard` 的 CTA 已经是显式 link（"所有项目" / "OKR 详情"），用户已能一键跳大页 —— 长按再加一层 surface 是冗余。
- "刷新此卡片" 是 nice-to-have 但 widget 数据已通过 `.task` 自动 fetch + `.refreshable` 全屏刷新，独立刷单卡的工程量 > 收益。
- 留给未来：当 widget 出现独立大数据源（如外部 API）时再加 per-widget refresh。

### 6. 审批申请项 ("我提交的" + 审批人 queue)

`ApprovalsListView.swift`（"我提交的"）：

| 位置 | 项 | 角色 | 备注 |
|---|---|---|---|
| 顶部 | 查看详情 | 普通 | NavigationLink(value:)，与 row tap 等价 |
| 中部 | 复制编号 | 普通 | UIPasteboard，UUID 字符串供工单使用 |
| 中部 | 复制审批意见 | 普通 | 仅 `reviewerNote` 非空时显示 |
| 中部 | 复制摘要 | 普通 | "类型 · 创建时间" 拼接，常用于 chat 求审 |

`ApprovalQueueView.swift`（审批人）：

| 位置 | 项 | 角色 | 备注 |
|---|---|---|---|
| 顶部 | 查看详情 | 普通 | 同 row tap |
| 中部 | 批准 | 普通 | 仅 pending + `kind.supportsWriteOnIOS`；走 PendingAction sheet |
| 中部 | 拒绝 | destructive | 同上；后续 ApprovalCommentSheet 强制填 reason |
| 底部 | 复制申请人 / 复制编号 | 普通 | 仅 profile 非空时显示申请人 |

### 7. 公告项 (`AnnouncementsListView.swift`)

| 位置 | 项 | 角色 | 备注 |
|---|---|---|---|
| 中部 | 复制内容 / 复制标题与内容 | 普通 | UIPasteboard |
| 中部 | 置顶 / 取消置顶 | 普通 | 仅 admin+ 可见，调 `togglePin` |
| 底部 | 删除公告 | destructive | hoisted `pendingDelete` confirmationDialog（与原 trash 按钮共用） |

### 8. 日报 / 周报项 (`ReportingListView.swift`)

| 位置 | 项 | 角色 | 备注 |
|---|---|---|---|
| 顶部 | 编辑 | 普通 | 弹 `DailyLogEditView` / `WeeklyReportEditView` sheet |
| 中部 | 复制内容 | 普通 | 日期 + content / 周报多段拼接 |
| 底部 | 删除 | destructive | hoisted `pendingDeleteDaily` / `pendingDeleteWeekly` confirmationDialog |

之前两段都是 `Button("编辑") { … }` 裸标签 + 直接 inline mutate delete，本轮按规范升级到 `Label(_, systemImage:)` + hoisted dialog + `Haptic.warning/error()` 区段。

---

## 已有但本次未改动的长按场景

仅记录，保持兼容：

- `Shared/Components/BsWeeklyCadenceStrip.swift` —— 7 个圆点 `onLongPressGesture(minimumDuration: 0.5)` → 弹 `DayPeekSheet`。
- `Features/OKRs/OKRListView.swift` —— Objective 行 `.contextMenu` 已挂 `objectiveContextMenu(obj)`（状态切换）。
- `Features/OKRs/OKRDetailView.swift` —— KR 行 `.contextMenu`（编辑 / 删除）。
- `Features/Deliverables/DeliverableListView.swift` —— 行 `.contextMenu`（编辑 / 删除）。

v1: 新增 5 项 + 已有 4 项 = 9 处。
v2: 再补 4 处 —— 我提交的 / 审批人 queue / 公告 / 日报+周报 = **13 处** 长按入口构成 v2 体系。
v3 (本轮): 见下方 §v3 长按系统升级 章节,新增 8 类 surfaces (含 Avatar 体系 + Dashboard widget 整卡 + Chat preview API + 排班/管理/知识库 audit) ≈ **20+ 处** 长按入口。

---

## 未来增项

1. **Chat 气泡 `.contextMenu(menuItems:preview:)`** —— 为气泡放大预览 + 顶部 reaction-picker（横向 emoji 行而非 Menu submenu）。
2. **Channel-picker 转发** —— 替代当前剪贴板版本。
3. **TaskEditSheet** —— 长按菜单加「编辑详情」入口。
4. **ProjectEditSheet / 归档** —— ProjectRowCard 加 destructive 项。
5. **通知 type 分类 + 静音此类** —— 需要先扩 `AppNotification.NotificationType` enum + 分类 muted_types 表。
6. **Dashboard widget 长按 = 快速预览** —— 当独立数据源出现时启用。

## 实施清单 / 自检

- [x] 每个 contextMenu Button 用 `Label(_, systemImage:)`
- [x] destructive 用 `Button(role: .destructive)`
- [x] 所有 destructive 经 `confirmationDialog` 二次确认
- [x] confirmationDialog 在 view 根部 hoist，不分散 per-row
- [x] menu 容器层不调 Haptic（依赖 iOS 自带 rigid）；项级独立 haptic
- [x] 菜单项数 ≤ 6
- [x] 文案中文动词起首；图标统一 SF Symbols
- [x] 与已有 swipe action 共享同一 destructive state（避免双向 race）

---

## §v3 长按系统升级 (2026-04-25)

参考 Slack iOS / iMessage tapback / Mail.app preview 三套交互范式,本轮覆盖 v2 deferred items + 全 app 长按入口审计。

### v3.1 — Chat 气泡 `.contextMenu(menuItems:preview:)` (iOS 26 API)

**文件:** `Features/Chat/ChatRoomView.swift`

替换 v2 的标准 `.contextMenu`,启用 iOS 26 双闭包 API:

- `preview:` —— 渲染 `enlargedPreview(msg:)`,系统自动做 zoom-in 弹动画 + 半透明遮罩(对齐 iMessage 气泡放大)。
- `menuItems:` —— **顶部横向 emoji reaction picker** (Slack iOS pattern):
  - `ControlGroup` 摊开 6 个 quickEmojis (👍 ❤️ 😂 😮 🎉 🔥) 作为独立按钮
  - 末尾 "+ 更多" Menu submenu 装 12 个 extendedEmojis (🤔 👀 🙌 …)
  - `.controlGroupStyle(.compactMenu)` 让按钮组紧凑横排,接近 Slack iOS 的 1-row picker
- `Divider` 后接 v2 既有的「回复 / 复制 / @提及 / 转发」+ destructive「撤回」
- 反应按钮点击 → `viewModel.toggleReaction(messageId:emoji:)` RPC + 系统自动 dismiss menu

### v3.2 — UserPreviewSheet (Slack iOS member sheet pattern)

**新增文件:** `Features/Team/UserPreviewSheet.swift`

`UserPreviewData` 轻量 view-model (id 必填, 其他全可选) + `UserPreviewSheet` 半屏 sheet:

- **Layout:** 84pt 大头像 → 姓名 + role pill → 3 个圆 quick actions(发消息 / 打电话 / 查看资料)→ info card(部门 / 职位 / 邮箱 / 电话) 各行
- **Detents:** `.fraction(0.4)` + `.large` —— 用户既能瞥也能展开
- **Quick actions:**
  - 发消息 → 复用 `ChatListViewModel.findOrCreateDirectChannel` + push `ChatRoomView`
  - 打电话 → `tel://` URL (仅 phone 非空)
  - 查看资料 → push `TeamMemberDetailView(userId:)`
- **Info row 嵌套 contextMenu:** 邮箱/电话行长按可"复制"

**应用 surfaces:**

| 文件 | 触发位置 | 数据来源 |
|---|---|---|
| `Features/Team/TeamDirectoryView.swift` | 卡片整体 contextMenu (memberContextMenu) + 头像独立 contextMenu | `TeamMember` |
| `Features/Approvals/ApprovalCenterView.swift` | `QueueRowView` 头像 contextMenu | `ApprovalActorProfile` (id?, fullName, avatarUrl, department) |
| `Features/Announcements/AnnouncementsListView.swift` | 作者头像 contextMenu | `AuthorProfile` (id?, fullName, avatarUrl) |

**未应用(写注释了原因):**
- ChatRoomView —— 当前设计不渲染消息气泡左侧 avatar,没有承接 view。
- TaskListView —— TaskCardView 不渲染 assignee avatar,只显示参与者数量。
- ActivityFeedView —— `ActivityActor` 没存 id,sheet 拿不到 user.id 无法跳转。

### v3.3 — BsWidgetCard 长按 API 扩展

**文件:** `Shared/DesignSystem/Primitives/BsWidgetCard.swift` (本轮唯一豁免的 design system 文件)

API 变更:
- 主 init 增加 `@ViewBuilder menu: () -> Menu` 必传参数
- 新增 `extension BsWidgetCard where Menu == EmptyView` 提供向后兼容的无菜单 init
- `BsWidgetCardMenuModifier` 把 `.contextMenu` 调用孤立到独立 view tree(避免 `BsContentCard` generic 解析失败)

**Dashboard 9 widgets 长按动作:**

| Widget | 跳转项 | 复制项 |
|---|---|---|
| MyTasksSection | 跳到任务管理 | 复制摘要(活跃 N · 进行中 N · 待处理 N · 逾期 N) |
| MonthlySnapshotSection | 跳到考勤页 (pushModule .attendance) | 复制本月摘要(出勤 / 出差 / 事假 / 调休 / 旷工) |
| ActiveProjectsSection | 跳到项目列表 | 复制项目清单 |
| MyOkrSection | 跳到 OKR 详情 | 复制目标清单 (含进度) |
| RecentActivitySection | 查看全部动态 (pushModule .activity) | — |
| ApprovalSummaryCard | 跳到审批中心 / 我审 我提 | — |
| RiskOverviewCard | — | 复制风险摘要 |
| TeamMonitorCard | 跳到团队 / 查看全员日报 | 复制团队摘要 |
| ExecutiveKPIsCard | 跳到 AI 分析 / 跳到财务 AI | 复制 KPI 摘要 |

`pushModule` 通过 ExecutiveKPIsCard / RecentActivitySection / MonthlySnapshotSection 的可选参数下传,DashboardView 在三处调用站补传。其他 widget 已有 `pushModule` 字段。

**为什么不全转 NavigationLink:** `pushModule` closure 把目标 append 到 `navPath`,与 dashboard 现有 value-based 路由一致(避免 List row 多 NavigationLink 的链式 push bug,见 Phase 28 修法)。

### v3.4 — 补漏长按场景 audit

| 文件 | Surface | 新增菜单内容 |
|---|---|---|
| `Features/Schedule/ScheduleView.swift` (`MyDayRow`) | 14 天排班行整行长按 | 快速请假 / 快速外勤 / 快速出差 + Divider + 查看排班详情 |
| `Features/Admin/AdminUsersView.swift` (`AdminUserRowView`) | 用户行 bsContextMenu(buildContextMenu()) | 编辑 / 修改角色(打开同 sheet) / 复制 ID + destructive 禁用账号 / 删除(仅非本人 + canManage) |
| `Features/Announcements/AnnouncementsListView.swift` | 作者头像 contextMenu | 查看资料(若 profile.id 非空) |
| `Features/Team/TeamDirectoryView.swift` | 卡片 memberContextMenu + 头像 contextMenu | 查看资料 / 发消息 / 复制电话(canViewDetails) |
| `Features/KnowledgeBase/KnowledgeListView.swift` | 文章行 contextMenu | 打开 / 打开附件 / 复制链接 / 重命名 / **destructive 删除** (走 hoisted `pendingDelete` confirmationDialog,与 swipe action 共享 state) |

**Chat 气泡 v3** 已在 §v3.1 单独描述,不重复。

### v3 体系自检

- [x] iOS 26 `.contextMenu(menuItems:preview:)` 在 chat 气泡接入,preview = enlarged bubble(白底 surfacePrimary) + 横向 reaction picker
- [x] UserPreviewSheet 半屏卡 + 3 quick actions,跨 3 个 surface 复用同一组件
- [x] BsWidgetCard 支持 `@ViewBuilder menu:` 闭包,9 个 dashboard widget 全员配置长按菜单
- [x] Schedule / Admin user / Knowledge 三个 audit surface 全部 v2 规范化(Label + hoisted dialog + Haptic 区段)
- [x] 头像长按动作不与卡片整体长按冲突 —— 头像 contextMenu 独立挂在 avatar view,只显示 profile-related 项
- [x] iOS sim build 通过(xcodebuild generic/platform=iOS Simulator)

### 仍未实施 (defer 到 v4)

- **Channel-picker 转发** —— 替代当前剪贴板版本(需要新组件 ChannelPickerSheet)
- **TaskEditSheet** —— 长按菜单加「编辑详情」入口(任务字段编辑能力不全)
- **ProjectEditSheet / 归档** —— ProjectRowCard 加 destructive 项
- **通知 type 分类 + 静音此类** —— 需要先扩 `AppNotification.NotificationType` enum + 分类 muted_types 表
- **ActivityFeedView avatar 长按** —— `ActivityActor` 缺 user id;需要 ViewModel 升级 select profile id
- **Chat 消息气泡左侧 avatar** —— 当前 ChatRoomView 不渲染 author avatar,要做需要先 redesign 气泡 layout(Slack iOS / Discord 风格头像列)
