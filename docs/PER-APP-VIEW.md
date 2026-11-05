# 每应用视角：最终目标（定死，不再改动）

> 这份文件是需求的**唯一权威定义**。任何实现、重构、内核改动都必须逐条满足它；
> 如果实现与本文冲突，改实现，不改本文。改动本文需要用户明确同意。

## 0. 不可违反的前提

1. **应用永远不能把自己隐藏起来**（自己必须能看见自己）。
   任何一层（磁盘/sus_path、PackageManager hook、挂载、探针）都必须先满足这条。
2. **两层必须一致**：磁盘层（内核 sus_path / policy.tsv）与 API 层（Zygisk `shouldHide`）
   对同一个 target 必须给出**完全相同**的可视集合。检测器会交叉验证这两层。
3. **一切以 HMA 的既有模板配置为准**，不引入第二套配置来源。

## 1. 三个类别

设 `W` = 白名单模板里的应用集合（`templates[*].appList`，`isWhitelist = true` 的所有模板的并集）。

### 类别 1：套了白名单模板，但自己**不在** W 里

例：春秋（`com.chunqiunativecheck`）、鸭子（`com.eltavine.duckdetector`）、Maple（`com.maple.detect`）
这类是**检测软件**。

- **能看见**：`W` 里的应用 + 自己
- **不能看见**：所有不在 `W` 里的应用（管理类、Root 工具、HMA 自己、其他检测器）

理由：检测器必须看到"正常应用的正常世界"才有意义；让它什么都看不见是自欺欺人。
同时它不能看到敏感应用，否则它会把它们报出来。

### 类别 2：套了白名单模板，且自己在 W 里

- **能看见**：`W` 里的应用（含自己）
- **能被看见**：因为它在 `W` 里，所有类别 1/2 的 target 都能看见它
- 它看不见 `W` 之外的应用

### 类别 3：没套模板，也不在 W 里

- **对所有人不可见**（任何类别 1/2 的 target 都看不到它）
- 如果它自己也是 target（配置了隐藏），它仍然**能看见自己**（前提 1）

## 2. 由此推出的实现规则

对任意 target `T`（`config.scope` 里有条目的应用）：

```
visible(T) = W ∪ {T} ∪ alwaysVisible
hidden(T)  = pool - visible(T)
```

其中：

- `pool` = 用户应用；若 `excludeSystemApps == false` 再加入系统应用；
  **再减去预装应用**（`/system /system_ext /product /vendor /odm /cust /apex`，MIUI 输入法在 `/product/data-app`）。
- `alwaysVisible` = `webViewProtection` 打开时的"当前 WebView 提供者 + 默认浏览器"（API 层本来就不隐藏它们）。
- 白名单模式（`useWhitelist=true`）与黑名单模式的差异只体现在 `extraAppList` / `extraOppositeAppList`，
  不改变上面这条主公式。

### 白名单不靠"显式套模板"生效

只要 target 是**白名单模式**（`useWhitelist = true`），它就自动看见 `W`，
**不要求** `applyTemplates` 里显式写着"白名单"。

原因：春秋这类检测器在配置里就是"白名单模式 + 没有勾选任何应用模板"，
而按类别 1，它必须看见 `W`。所以 `W` 对白名单模式是**隐式生效**的。

## 3. 三个类别的判定（用当前设备的真实数据核对）

| 应用 | 模板 | 在 W 里 | 类别 | 应看到 |
|---|---|---|---|---|
| 春秋 | —— | 否 | 1 | W + 自己 |
| 鸭子 | —— | 否 | 1 | W + 自己 |
| Maple | —— | 否 | 2 | W（含自己） |
| HMA / Magisk / KSUNext / Scene / ReSukisu | —— | 否 | 3 | 只能看见自己（对他人不可见） |

> 注：上表的"模板"列按 `config.json` 现状（`applyTemplates` 为空）；
> 这不影响结论，因为类别 1 的白名单可见性是隐式生效的。

## 4. 验收标准

改动后必须同时满足：

1. 春秋：`隐藏应用列表生效` **不出现**；并且它不是"瞎子"——
   能列出 `W` 里的应用（例如随便挑一个白名单应用，检测器能看到它）。
2. 春秋/鸭子/Maple **看不到** HMA、Magisk、KernelSU、Scene、ReSukisu。
3. 鸭子：0 Danger。
4. Maple：ALL CLEAR，0 危险 0 可疑。
5. 每个 target 都**能看见自己**（不能被自己的规则隐藏）。
6. `policy.tsv`（磁盘层）与 API 层的 hidden 集合对每个 target **完全一致**。

## 5. 当前实现状态

- 磁盘层：`ConfigManager.getSusfsTargetHides()`
- API 层：`HMAService.shouldHide()`
- 内核：policy.tsv 由 `sync.sh` 生成，经 `ksu_susfs add_sus_path_hide_from /data/adb/hma_susfs/.abk-policy 0`
  一次性加载（`ABK/.github/scripts/patch_susfs_policy_file.py`）。

任何一层改动后，都要按 §4 重新验收，并更新 `MEMORY.md`。
