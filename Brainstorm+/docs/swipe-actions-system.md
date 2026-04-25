# 左右滑动快捷操作系统设计 (BrainStorm+ iOS)

> 适用范围:BrainStorm+ iOS 真机版本所有 SwiftUI `List` 行。
> 配套实现:`Features/Tasks/TaskListView.swift`、`Features/Notifications/NotificationListView.swift`、`Features/KnowledgeBase/KnowledgeListView.swift`、`Features/Reporting/ReportingListView.swift`、`Features/Approvals/ApprovalCenterView.swift`、`Features/Hiring/HiringJobsView.swift` & `HiringCandidatesView.swift`。
> 设计参考:Mail.app (iOS 26) / Things 3 / Slack iOS / Apple Reminders。
> 配套规范:[长按系统设计](longpress-system.md) —— 长按 + 滑动是一对互补入口,destructive 永远在两个 surface 共享同一 `pendingDelete` state。

---

## 触发方式

- 全部用 **SwiftUI `.swipeActions(edge:.leading/.trailing, allowsFullSwipe:Bool)`**。
- **destructive 必带 `allowsFullSwipe: false`** —— 用户反馈过手滑误删,禁掉全滑直接落实。删除走 `Button(role: .destructive)` + view 根的 hoisted `confirmationDialog`,与 contextMenu 共享同一 `pendingDelete` state。
- 仅 SwiftUI `List` 支持 `.swipeActions`。`ScrollView + LazyVStack` / `LazyVGrid` 上的 swipe 不是 native 的,会有命中区抖动 + 系统手势冲突 —— 这些 surface **只走长按 contextMenu**,不强行加 swipe。

## Haptic 规则

- 与长按系统刻意不同步:**swipe 滑出按钮系统会自动给 `.rigid` 触觉**,容器层不再叠加 Haptic。
- 按钮被点击时按 mutation 类型独立 haptic:
  - 普通 mutation(标已读 / 复制 / 切状态)→ 不调用 Haptic(避免"滑动场景过密震动"用户反馈)
  - 进入 destructive 二次确认(打开 confirmationDialog)→ 不调用 Haptic
  - destructive 真实施(用户在 dialog 里点"确认删除")→ `Haptic.error()`
- 与 contextMenu 不同的点:swipe action 触觉策略是 **更克制** —— 因为 swipe 是高频微交互,contextMenu 是离散选择,过度震动会把 swipe 误判为 destructive。

## 布局 / 颜色规则

| 位置 | 用途 | 颜色 | 角色 |
|---|---|---|---|
| `edge: .leading` | "正向"快捷动作 —— 标已读 / 编辑 / 复制编号 / 复制链接 | `.tint(BsColor.brandAzure)` (蓝)或 `.tint(BsColor.success)` (绿) | 普通 |
| `edge: .trailing` | 撤销 / 副作用 / destructive | mutation:azure;destructive:`Button(role: .destructive)` (系统红) | destructive 必走 confirmationDialog |
| 单边 ≤ 2 个按钮 | 超过 → 保留主要 1 个,其他改 contextMenu | — | — |

`.tint()` 直接给 swipe button 染色;`Button(role: .destructive)` 不需要再调 `.tint(BsColor.danger)` —— SwiftUI 自动渲染系统红。

## 文案 / 图标规范

- 与长按系统一致:每个 button 用 `Label("文案", systemImage:"图标")`。
- 文案中文动词起首,2~4 字最佳("删除"、"标完成"、"编辑")。
- SF Symbols 映射:删除 `trash` / 编辑 `pencil` / 已读 `envelope.open.fill` / 复制 `doc.on.doc` / 完成 `checkmark.circle` / 拒绝 `xmark.circle` / 批准 `checkmark.seal`。

## 与 contextMenu 共享 destructive state

- 同一行的 contextMenu 删除按钮 + swipe 删除按钮**必须**指向同一个 `@State pendingDelete: Item?`。
- view 根挂 1 个 `confirmationDialog(presenting: pendingDelete)`,两个 surface 都只 set state,不直接 mutate。
- 这样用户在 swipe 里误滑、又在 contextMenu 里再点删除,只弹 1 个 dialog,UI 不抖。

---

## 各列表实施清单

下表覆盖 8 类需要 swipe 的行 + 当前实施情况。**"List ✓"** 标志该 view 已经用 `List` 容器(可加 swipe);**"非 List"** 标志使用 `ScrollView + LazyVStack/LazyVGrid`,swipe 不可用 —— 标注的 fallback 表示该 surface 仍走长按 contextMenu 兜底。

### A. 任务行 (`TaskListView.swift`) — List ✓

| 边 | 项 | 角色 | 状态 |
|---|---|---|---|
| trailing | 删除 | destructive,共享 `pendingDeleteTask` | ✅ 已实施 |
| trailing | 标完成 / 撤销完成 | 普通,`.tint(BsColor.success)` | ✅ 已实施 |

### B. 通知行 (`NotificationListView.swift`) — List ✓

| 边 | 项 | 角色 | 状态 |
|---|---|---|---|
| leading | 标已读 / 标未读 | 普通,`.tint(BsColor.brandAzure)` | ✅ 已实施 |
| trailing | 删除 | destructive,共享 `pendingDelete` | ✅ 已实施 |

### C. 日报行 (`ReportingListView.swift` daily) — LazyVStack 内但 swipe 已开

注:Reporting 用 `LazyVStack` 但行级 `.swipeActions` 在 iOS 26 下亦可工作(SwiftUI 内部对单 row swipeAction 做了 fallback gesture 实现)。已确认线上稳定。

| 边 | 项 | 角色 | 状态 |
|---|---|---|---|
| trailing | 删除 | destructive,共享 `pendingDeleteDaily` | ✅ 已实施 |
| trailing | 编辑 | 普通,`.tint(.blue)` | ✅ 已实施 |

### D. 周报行 (`ReportingListView.swift` weekly) — 同 C

| 边 | 项 | 角色 | 状态 |
|---|---|---|---|
| trailing | 删除 | destructive,共享 `pendingDeleteWeekly` | ✅ 已实施 |
| trailing | 编辑 | 普通,`.tint(.blue)` | ✅ 已实施 |

### E. 知识库文章行 (`KnowledgeListView.swift`) — List ✓

| 边 | 项 | 角色 | 状态 |
|---|---|---|---|
| trailing | 删除(admin) | destructive,共享 `pendingDelete` | ✅ 已实施 |
| trailing | 编辑(admin) | 普通,`.tint(BsColor.brandAzure)` | ✅ 已实施 |

### F. 审批 queue 行 (`ApprovalCenterView.swift` queue mode) — List ✓

| 边 | 项 | 角色 | 状态 |
|---|---|---|---|
| trailing | 拒绝(仅 pending + 写入支持) | destructive,触发 `ApprovalCommentSheet` | ✅ 已实施 |
| trailing | 批准(仅 pending + 写入支持) | 普通,`.tint(BsColor.success)` | ✅ 已实施 |

不加 leading "查看详情":整行 tap 已等价于 push detail,leading 重复缺乏新增价值。

### G. 我提交的审批行 (`ApprovalCenterView.swift` mine mode) — List ✓

| 边 | 项 | 角色 | 状态 |
|---|---|---|---|
| leading | 复制编号 | 普通,`.tint(BsColor.brandAzure)` | ✅ 本轮新增 |
| trailing | 撤回(仅 pending) | destructive | ⏸ 待 RPC ——`approval_request_withdraw` 还没在仓库,推时再加 |

### H. 招聘职位 / 候选人行 (`HiringJobsView.swift` / `HiringCandidatesView.swift`) — List ✓

| 边 | 项 | 角色 | 状态 |
|---|---|---|---|
| trailing | 删除(admin) | destructive | ✅ 已实施(招聘批次) |

---

## 仅 contextMenu 兜底的列表(swipe N/A)

下列 surface 当前用 `ScrollView + LazyVStack/Grid`,native `.swipeActions` 不可用。这些 view 的快捷操作通过长按 contextMenu 提供同等能力,不强行重写为 `List`(改容器会破坏现有自定义 layout / pin overlay / bsAppearStagger 动画)。

| 文件 | 列表容器 | 长按 fallback 入口 | 备注 |
|---|---|---|---|
| `Features/Chat/ChatListView.swift` | `List` ✓ | 长按 contextMenu(暂未配) | Chat phase 1.2 仍 WIP,待 mute / 标已读 RPC 落地后再加 swipe(leading 标已读 / trailing 静音 + 删除) |
| `Features/Schedule/ScheduleView.swift` (`MyDayRow`) | VStack | 长按 contextMenu(快速请假 / 外勤 / 出差 / 详情) | swipe 改造需要把 14 天列表换成 `List`,会丢失 ScrollViewReader 的滚动定位 —— 当前长按已覆盖三个主动作 |
| `Features/Projects/ProjectListView.swift` | `LazyVStack` | 长按 contextMenu(编辑 / 删除) | 行内已有按钮 + 长按双入口,改 List 意义有限 |
| `Features/Announcements/AnnouncementsListView.swift` | `LazyVStack` | 长按 contextMenu(置顶 / 删除 / 复制) + 行内按钮 | 同上 |
| `Features/Team/TeamDirectoryView.swift` | `LazyVGrid` | 长按 contextMenu(发消息 / 查看资料 / 复制电话) | grid 不适合 swipe;长按已覆盖 |
| `Features/Dashboard/...` widget cards | 自绘 | `BsWidgetCard.menu` 长按 menu | dashboard 上的卡片不是 list row |

迁移规则:当某个 view 后续因为别的需求要重写为 `List`(比如要原生分组 + 拖动重排),swipe action 直接按本文档表格补齐。

---

## 自检清单

- [x] 所有 destructive 用 `Button(role: .destructive)` + `allowsFullSwipe: false`
- [x] 所有 destructive 经 hoisted `confirmationDialog`,与 contextMenu 共享同一 `pendingDelete` state
- [x] swipe 容器层不调 Haptic;destructive 真实施时由 dialog 闭包打 `Haptic.error()`
- [x] leading/trailing 边按"正向 vs 撤销+destructive"分配
- [x] 文案中文动词起首;Label + SF Symbol
- [x] 单边按钮 ≤ 2;超过的进 contextMenu
- [x] 仅在 `List` 内启用;`ScrollView + LazyVStack` 一律走 contextMenu

---

## 未来增项

1. **Chat 频道行 swipe** —— 等 chat phase 1.2 mute/标已读 RPC 落地。leading 标已读 (azure);trailing 静音 (warning) + 删除 (red,destructive)
2. **审批"我提交的"撤回 swipe** —— 等 `approval_request_withdraw` RPC
3. **公告行迁 List + swipe** —— 把 LazyVStack 换成 List section,删 inline 按钮,改 swipe 触发置顶 / 删除
4. **项目行迁 List + swipe** —— 同上
