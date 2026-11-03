# 更新日志

本仓库包含 SUSFS per-target 隐藏的内核补丁、`ksu_susfs` CLI 构建，以及 HMA-OSS 设备侧同步脚本。
条目按日期倒序，按「修复 / 新增 / 文档 / 构建」分类。

## 2026-11-03

### 修复

- **撤掉「风险应用全局隐藏」。**
  中午那版把「不在任何白名单模板、也没有应用模板」的用户应用用
  `add_sus_path_loop <path> <owner_uid>` 对**所有 app** 隐藏；春秋随即在自己的包清单里看到这些包、
  但它们的 `/data/data` 目录消失，于是报「隐藏应用列表生效」。
  磁盘层必须与 `ConfigManager.getSusfsTargetHides()` 的视角一致：只对配置了隐藏的 target 隐藏，
  绝不做全局隐藏。`buildPkgsList()` 改回 `emptyList()`。
- **恢复 per-target 的两条外部路径**（`/storage/emulated/0/Android/data/<pkg>`、
  `/data/media/0/Android/data/<pkg>`），与中午之前的脚本保持一致（FUSE 上受 ino-0 守卫限制，但保留无副作用）。

- **白名单模板里的应用现在对所有应用可见（模块侧）。**
  `HMAService.shouldHide()` 只认「调用方自己应用的模板」，白名单模式下没被列到的包一律隐藏；
  而 `excludeSystemApps` 的豁免按 `FLAG_SYSTEM` 判断，像讯飞输入法这种装在
  `/product/data-app` 的 **product 预装应用没有 system flag**，于是被隐式隐藏
  → Maple 交叉核对「当前输入法」与「包查询结果」时报 `component_invisible: 1`。
  现在缓存「所有白名单模板 appList 的并集」，在隐式隐藏前先返回可见（配置重载时失效缓存）。
  这是磁盘层 `ConfigManager.getSusfsTargetHides()` 同名改动的 API 侧对应实现。
- **刷完新 APK 后实际跑的还是旧脚本。**
  `/data/adb/hma_susfs/sync.sh` 只在「完整同步」时由 App 写入，开机脚本跑的是磁盘上的旧版本，
  新逻辑看起来完全没生效。新增 `SusfsSyncer.deployScript()`，`MyApp.onCreate` 每次启动刷新脚本。
- **去掉安装/卸载广播同步。** MIUI/HyperOS 直接拒绝把 `ACTION_PACKAGE_ADDED` 派发给第三方应用
  （`MIUILOG- Reject ACTION_PACKAGE_ADDED dispatch to ...`），manifest 声明同样被拦；
  同步改为「手动同步 + 开机后 120s 一次」，行为可预期。

### 新增

- **字典支持清除（prune）。** 每次同步结束后把 `state.tsv` 重写为本次配置算出的 desired 集合：
  配置里消失的条目（应用卸载、模板删除）会被统计为 `pruned` 并从字典移除；
  内核里已下发的条目不追溯（SUSFS 无删除接口），卸载场景无影响，配置回退需重启才恢复可见。
- **两阶段同步。** 先用一次 `stat` + awk join 建「包名→uid」映射并生成 desired 列表，再 `sort`/`comm`
  求差集，只对差集调用 `ksu_susfs`；无变化同步从 **2m26s 降到 3.4s**，全量 `--reset` 约 1m35s（CLI 开销）。

## 2026-11-02

### 新增

- **隐藏列表全部改为路径驱动，不再依赖 inode。**
  `sus_path` 是按 inode 记账的：inode 被回收、或 app 数据目录重建（卸载/重装/更新）后，
  `AS_FLAGS_*` 会随 inode 消失，配置还在但隐藏失效——表现就是「刚同步好、过一会又复现」。
  - `pkgs.txt` 里的包路径：`add_sus_path()` 辅助函数直接调用 `add_sus_path_loop`
    （不再探测路径是否存在，loop 允许路径稍后才创建）；
  - per-target 和额外路径：沿用 `add_sus_path_hide_from`，由配套内核补丁
    `SUS_PATH_LOOP_MODE_ABK` 入队成 `mode 1`，同样在每次 app 启动时按路径重放；
  - 逐 target 的 `add_hidden_uid_from` 不变。
- **`<PKG>` 额外路径占位符现在真正生效。** 之前只遍历 `pkgs.txt`（per-target 模式下它是空的），
  改成 `targets.txt` 第 2 列 ∪ `pkgs.txt` 去重后展开，并输出展开数量；无包可展开时给出
  `SUSFS_SYNC_WARN`。

### 修复

- **`sync.sh` 以 CRLF 发布导致同步失败。** mksh 报
  `sync.sh[N]: : inaccessible or not found` / `syntax error: unexpected 'newline'`，
  同步退出码 1。新增 `.gitattributes`（`*.sh text eol=lf`）并把三个随包发布的脚本归一化为 LF。
- **额外路径会把属主自己也隐藏。** 检测器既是被隐藏包、又是 target 时，
  `/data/data/<检测器>` 会被 deny 给它自己，读不到自己的数据（表现为用户协议页闪退）。
  展开时用 `stat -c %u <path>` 取路径属主，跳过 `target_uid == owner_uid`；
  `sync_target_hides` 也加了 self-pair 保护。

### 构建

- **Gradle 仓库改为官方优先。** `google()` / `mavenCentral()` / `jitpack.io` 放最前，
  阿里云、腾讯镜像降为 fallback。镜像偶发 502 会让 Gradle 把整个仓库禁用
  （`Repository maven is disabled due to earlier error`），之前两次 APK 构建就是挂在
  Aliyun 502 和 JitPack 的 `ZygoteLoader` 上。

### 说明

- 与 ABK 内核补丁的配套关系：
  `SUS_PATH_LOOP_MODE_ABK`（loop 条目带 `mode`、`hide_from` 入队）、
  `SUSFS_SUS_TYPE_REG_ABK`（BakaSU 的 SELinux type/AVD 注册）。
- **教训：FUSE 的 `i_ino` 是 0，per-uid 表会退化成通配符。**
  `/storage/emulated/0` 是 FUSE，子项不实例化 inode，`i_ino` 为 0；
  `add_sus_path_hide_from` 按 `(ino, dev, uid, mode)` 记账，于是 `ino 0` 条目会命中
  **所有**未实例化的 FUSE inode——一个 app 只要同时是 target，就会读不到自己的
  `/sdcard/Android/data/<pkg>`（原神表现为「资源下载失败」）。
  内核侧已用 `patch_susfs_ino_zero_guard.py` 修掉（ABK `3f26140`）；
  FUSE 路径的 per-target 隐藏因此不再生效，`/data/*` 不受影响。
- 下次同步上游 SUSFS 时的核对清单见 ABK 仓库 `docs/susfs-sync.md`。

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
