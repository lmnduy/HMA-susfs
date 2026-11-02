# 更新日志

本仓库包含 SUSFS per-target 隐藏的内核补丁、`ksu_susfs` CLI 构建，以及 HMA-OSS 设备侧同步脚本。
条目按日期倒序，按「修复 / 新增 / 文档 / 构建」分类。

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
