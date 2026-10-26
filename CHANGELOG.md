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
