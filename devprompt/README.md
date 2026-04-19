# BrainStorm+ iOS DevPrompt

当前只投放一个开发轮次。

## 当前轮次
- `2.6-projects-risk-action-sync-write-path-foundation.md`

## 节奏规则
1. 先执行当前轮次开发。
2. 在放入每一轮新 prompt 前，必须先扫描本地所有 skills，再选择本轮最匹配 skills，并在 prompt 中强制要求使用。
3. 完成后由 Winston 审计。
4. 审计通过，才创建下一正式轮次。
5. 审计不通过，则由 Winston 创建当前轮次的最小修复轮；当前 `2.5.1` 已审计通过，已切换到下一正式轮 `2.6`。
6. 不提前一次性生成后续轮次。

## 最终目标
iOS App 必须与 Web 端数据实时共享互通同步，设计语言、材质、配色、logo 一致，功能 1:1 原生重构，并具备优秀 iOS 动效与交互。
