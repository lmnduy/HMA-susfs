# 更新日志

本仓库包含 SUSFS per-target 隐藏的内核补丁、`ksu_susfs` CLI 构建，以及 HMA-OSS 设备侧同步脚本。
条目按日期倒序，按「修复 / 新增 / 文档 / 构建」分类。

## 2026-10-26

### 修复

- **同步只使用 `/data/adb/hma_susfs/bin/ksu_susfs`。**
  KernelSU 的 `ksud` 是多调用程序，会在开机以及每次打开管理器时把
  `/data/adb/ksu/bin/ksu_susfs` 重链到自身；该 applet 不认
  `add_hidden_uid_from` / `add_sus_path_hide_from`（实测报
  `unrecognized subcommand`，二进制 5,955,504 B）。此前任何通过 `PATH`
  或 `/data/adb/ksu/bin` 解析工具的同步都会静默失败，表现为「隐藏过又复现」。
  - `device/hmaoss.sh`（及 `hma-oss/zygote/src/main/assets/hmaoss.sh`）：
    不再写入 `/data/adb/ksu/bin`，不再使用 `command -v` 回退；部署只写私有路径；
    同步前用 `add_hidden_uid_from` 做能力探测，不通过则输出日志并跳过。
  - `device/susfs_sync.sh`（及 `hma-oss/app/src/main/assets/susfs_sync.sh`）：
    删除 6 条路径的搜索与 `command -v` 回退；工具缺失时只从模块挂载点补部署，
    绝不回退到 ksud applet；自检失败输出 `SUSFS_SYNC_ERROR` 并以 3 退出。

### 说明

- 两类失败容易混淆，排查时先看时间线：若 `targets.txt` 在开机同步之后才由管理器写入，
  内核里不会有任何 per-target 条目，重启或手动重跑 `susfs_sync.sh` 即可恢复；
  而工具路径被 `ksud` 顶替属于下一次必然踩到的坑，本次一并堵死。
- 手动重跑同步的成功标志：`sync.sh` 输出 `SUSFS_SYNC_OK`。

## 2026-10-21

### 文档

- 新增故障排查：容器运行时（Droidspaces / Anland）在 `/dev/<x>/<y>` 挂载 debugfs
  造成的「挂载间隙」，以及 SUSFS 同步失败的判定方法。

## 2026-10-18

### 新增

- 以 vendored 方式引入 HMA-OSS 源码（`hma-oss/`），APK 与模块均由本仓库构建，
  不再依赖上游不存在的提交。
- `patches/apply-all.sh` 固定补丁顺序：行尾归一化 →
  `60_add_per_uid_sus_path.patch` → `patch_susfs_hide_from_uid.py`（`0x55554`）→
  `patch_susfs_hidden_uid.py`（`0x55555`）→ `patch_susfs_hidden_uid_oracle.py` →
  `patch_susfs_hidden_uid_from.py`（`0x55556`，CLI 走 `ABK_CLI_ONLY=1`）。

### 构建

- CI 改用 runner 预装的 NDK（`nttld/setup-ndk@v1` 恒 404）。
- `apply-all.sh` 改为经 `bash` 调用（上传后的权限是 0644）。
- 修正 `gradlew` 的 chmod 行不再引用 `patches/`。

### 文档

- 记录构建拆分、补丁顺序与 Windows 上 CRLF 导致锚点失配的陷阱。

## 2026-11-06 — 内核侧整表加载 + per-app 视角定版

### 内核（ABK）
- **`patch_susfs_policy_file.py`（新）**：`ksu_susfs add_sus_path_hide_from /data/adb/hma_susfs/.abk-policy 0`
  让内核读取 `policy.tsv`（`mode|uid|path`），在**一次系统调用**里建好整张 per-target sus_path 表；
  实测 `policy: applied 3439 entries`，替代原先数千次用户态调用。
- **`patch_susfs_mount_per_uid.py`（新）**：挂载视图按 uid 门控（`4|uid|1` 位图），
  并让 `fs/namespace.c`（路径解析）与 `fs/proc/fd.c`（fdinfo）使用**同一判据**，
  修复「挂载视图不一致」类检测。
- **isolated 进程自动受管**：`90000–99999` 视为受管，修复以 WebView 沙箱进程为 baseline 的
  「cross-process mount tables diverge」。
- 经验：`proc_namespace.c` 三处入口只能**改条件**，不能守护 return（否则 `-Werror=return-type`）；
  头文件不保证可见时需就地 `extern`。

### 模块 / APK
- `sync.sh` 改为「收集 → 写 `policy.tsv` → 一次下发」，旧内核自动回退逐条；并下发 `4|<uid>|1` 受管 uid。
- 模块自带 `sync.sh`，开机脚本先安装再执行；开机同步固定在 **开机 120s 且用户存储就绪之后**。
- **白名单语义（spec-v2）**：`visible(T) = W ∪ {T} ∪ alwaysVisible`，`hidden(T) = pool − visible(T)`；
  白名单模式**隐式**看见 `W`；永不自隐藏；两层（磁盘/PM）同源。
- 修复：`shouldHide()` 内重入 PM 查询导致卡死（改为启动时一次性建集合）；
  属性声明顺序导致 hook 未安装（`preinstalledApps` 必须在 `init{}` 之前）。
- 磁盘层补上 WebView/默认浏览器豁免，与 API 层对齐。

### 验收
- 春秋：仅「USB 调试已开启」（开机同步的「挂载间隙」为瞬态，同步结束自愈）
- 鸭子：0 Danger
- Maple：ALL CLEAR（258/258）
## 2026-11-14 — 磁盘层隐藏闭环 + 内核并发/失败语义修正

### 根因修复（此前「三件套全绿但磁盘层没生效」）
- **策略加载器对所有规则入队**（原来只投 `mode 2`，而 `sync.sh` 生成的全是 `mode 1`）：
  inode 被回收后 `AS_FLAGS_SUS_PATH_HIDE_FROM` 再没人重新置位，谓词 `flag && denied` 永不成立。
  修复后加载时新增 **2369** 条 loop 队列，探针实测 `denied=1` 命中、`dataMissing` 出现 HMA/HyperCeiler/Scene。
- **FUSE `ino == 0`**：用 `get_fuse_inode()` 解析真实 inode；解析不到计 `deferred` 并投队列，
  不再计 `failed`（此前每次同步以 `-EIO` 收场，用户态误判「内核无 loader」）。
- **`sync.sh` 不再把「内核拒绝」当「内核不支持」**：空策略文件探测 loader，被拒报
  `SUSFS_SYNC_ERROR` 并非 0 退出；只有真不支持才逐条回退。

### 内核（ABK）
- 策略加载加**专用互斥量**（可睡眠操作，全部返回路径释放锁）。
- 受管 uid 集合：**双缓冲 + RCU 发布**（读者不再看到半清空集合）；4096 槽开放寻址支持多用户 uid；
  `statfs` 与 mountinfo/路径/fdinfo 统一判据；isolated（90000–99999）自动受管。
- Review 修复：readdir 缓存命中分支查表、oracle 钩子加 `CONFIG_KSU_SUSFS_SUS_PATH` 守卫、
  CLI 补 `CMD_SUSFS_ADD_HIDDEN_UID_FROM` 宏、kstat 锚点容错且只伪装身份字段、
  `add_sus_path` 的 `uid < 0` 现会撤销旧可见 uid（RCU 安全批量删除）。

### 验收
春秋 4.6.3 仅「USB 调试」；鸭子 0 Danger / 2 Warning；Maple 2.3.0 ALL CLEAR 260/260。
内核 `ab10000045`（tag `known-good-kernel-ab10000045`），模块/APK `a9258e4`，HMA tag `known-good-2026-11-14`。