# 00 Source of Truth

## 1. 业务 Source of Truth (Web)
- `nav-config.ts`: 定义了所有执行、报告、人事、沟通、管理的路由与模块入口。

## 2. 数据与 Schema Source of Truth (Web)
- `src/types/database.ts`: Supabase table definitions.
- `supabase/migrations/*.sql`: Actual database schema definition.

## 3. 权限与 RBAC Source of Truth (Web)
- `src/lib/capabilities.ts`: 4 primary roles + capability list.
- `src/lib/rbac.ts`: Role-based access control.
- `src/lib/scope.ts`: filtering constraints (self/department/project/org).

## 4. 设计 Source of Truth (Web)
- `src/app/globals.css`: 实际主导颜色的 CSS 变量 (Azure Blue #0080FF + Mint Cyan #00E5CC)。
- `design-system/brainstorm+/MASTER.md`: 设计系统文档，包含 motion、shadow 及间距等属性。

## 5. 设计冲突说明
- `MASTER.md` 与 `globals.css` **存在冲突**：`MASTER.md` 中 Primary 颜色仍定义为 Teal `#0D9488`，而实际网页前端按 `globals.css` 渲染为 Azure Blue `#0080FF`。
- **当前结论**：以实际运行的 `globals.css` 为准，优先对齐 Azure Blue 规范。

## 6. iOS 当前已有对齐文件
- `Brainstorm+/Shared/Security/RBACManager.swift`: 已初步映射能力。
- `Brainstorm+/Shared/Theme/Color+Brand.swift`: 需要对标 `globals.css` 的新值。

## 7. 后续所有轮次 Source of Truth 遵循顺序
1. **数据/Schema**: 数据库 `migrations/` > `database.ts`。
2. **权限**: `capabilities.ts` > `rbac.ts`。
3. **设计**: `globals.css` > `design-system/**/*.md` > `MASTER.md`。
4. **业务路由**: `nav-config.ts` > pages。