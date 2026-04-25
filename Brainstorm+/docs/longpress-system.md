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

---

## 已有但本次未改动的长按场景

仅记录，保持兼容：

- `Shared/Components/BsWeeklyCadenceStrip.swift` —— 7 个圆点 `onLongPressGesture(minimumDuration: 0.5)` → 弹 `DayPeekSheet`。
- `Features/OKRs/OKRListView.swift` —— Objective 行 `.contextMenu` 已挂 `objectiveContextMenu(obj)`（状态切换）。
- `Features/OKRs/OKRDetailView.swift` —— KR 行 `.contextMenu`（编辑 / 删除）。
- `Features/Deliverables/DeliverableListView.swift` —— 行 `.contextMenu`（编辑 / 删除）。

新增 5 项 + 已有 4 项 = **9 处** 长按入口构成 v1 体系。

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
