# 每应用视角：最终目标（定死版 v2，2026-11-05）

> 这份文件是需求的**唯一权威定义**。任何实现、重构、内核改动都必须逐条满足它；
> 实现与本文冲突时，**改实现，不改本文**。改动本文需要用户明确同意。
>
> 冻结标签：`spec-v2`（git tag）。此文件也备份在
> `backups/spec-v2-desktop/PER-APP-VIEW.md`，桌面端另存一份。

## 0. 不可违反的三条

1. **任何应用都必须能看见自己**（永远不隐藏自己）。
   磁盘层、PackageManager 层、挂载、探针，全部适用。
2. **两层一致**：磁盘层（`policy.tsv` → 内核 per-uid sus_path）与 API 层（Zygisk `shouldHide`）
   对同一个 target 必须给出**完全相同**的可视集合。检测器会交叉验证这两层。
3. **一切以 HMA 既有的模板配置为准**，不引入第二套配置来源。

## 1. 三个类别（这是全部语义）

记号：`W` = 白名单模板里的应用集合（所有 `isWhitelist = true` 模板的 `appList` 并集）。
`T` = 某个应用（target）。

| # | 条件 | 能看见谁 | 谁能看见它 | 典型 |
|---|---|---|---|---|
| 1 | 套了白名单模板，**自己不在 W 里** | `W` + 自己 | **只有它自己**（别人看不到它） | 春秋、鸭子、Maple 等检测器；强度高的游戏/银行检测 |
| 2 | 套了白名单模板，**自己在 W 里** | `W`（含自己） | 所有类别 1/2 的 target（因为它在 `W` 里） | 日常软件 |
| 3 | **没套模板，也不在 W 里** | 只有自己 | **没有人**（对所有人不可见） | Root 管理器、HMA 自己、Root 工具等高风险应用 |

为什么类别 1 要"别人看不到它"：高强度检测（游戏/银行）会把"检测器的存在"本身当成 root 标识，
所以检测器必须从它们的视野里消失；同时检测器自己必须看得见正常世界（`W`），否则"通过检测"毫无意义。

## 2. 由三类推出的唯一公式

对任意 target `T`：

```
visible(T) = W ∪ {T} ∪ alwaysVisible
hidden(T)  = pool − visible(T)
```

- `pool`：用户应用；`excludeSystemApps == false` 时再加系统应用；**再减去预装应用**
  （`/system /system_ext /product /vendor /odm /cust /apex`——MIUI 输入法在 `/product/data-app`）。
- `alwaysVisible`：`webViewProtection` 打开时的"当前 WebView 提供者 + 默认浏览器"（API 层本来就不隐藏它们）。
- `extraAppList` / `extraOppositeAppList` 只在此基础上做增减，不改变主公式。

**白名单模式隐式生效**：只要 target 是白名单模式（`useWhitelist = true`），它自动看见 `W`，
不要求 `applyTemplates` 里显式写着"白名单"（春秋在配置里就是白名单模式 + 未勾模板）。

## 3. 与实现的对应

| 层 | 位置 | 如何满足 |
|---|---|---|
| 磁盘 | `ConfigManager.getSusfsTargetHides()` | `visible` 以 `W ∪ alwaysVisible` 初始化，`hidden = pool − visible`，最后 `hidden.remove(T)` |
| API | `HMAService.shouldHide()` | `if (query in globalWhitelist) return false`；`globalWhitelist` 在 `loadConfig()` 重建 |
| 内核 | `sync.sh` → `policy.tsv` → `ksu_susfs add_sus_path_hide_from .abk-policy 0` | 一次性整表加载（`patch_susfs_policy_file.py`） |

## 4. 验收（每次改动后必须全部满足）

1. 春秋：不出现「隐藏应用列表生效」；且**不是瞎子**（白名单应用可见）。
2. 春秋/鸭子/Maple **看不到** HMA、Magisk、KSUNext、Scene、ReSukisu，以及**彼此**。
3. 任意 target 的 hidden 集合里**不含它自己**。
4. 鸭子 0 Danger；Maple ALL CLEAR（0 危险 0 可疑）。
5. `policy.tsv` 推导出的集合与 API 层完全一致。

### 本机实测（2026-11-05，`d9a5de0` / `known-good-2026-11-05c`）

| 检测器 | 看不到的包（从 policy.tsv 按 uid 导出） |
|---|---|
| 春秋 10284 | HMA、ReSukisu、HyperCeiler、Scene、bin.mt.plus、droidspaces、viewprobe、**鸭子、Maple**、tmall 检测 |
| 鸭子 10336 | HMA、ReSukisu、HyperCeiler、Scene、…、**春秋、Maple** |
| Maple 10299 | HMA、ReSukisu、HyperCeiler、Scene、…、**春秋、鸭子** |

- 每个 target 的 hidden 集合都不含自己 ✅
- 春秋/鸭子：1 项（USB）/ 0 Danger；Maple：ALL CLEAR 259/259 ✅

## 5. 变更记录

- v1（初版）：三类别草稿，含"仅公式"。
- **v2（本文，冻结）**：补上"谁能看见它"维度（类别 1 对他人不可见）、明确白名单模式隐式生效、
  加入实现对应表与实测数据。
