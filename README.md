# SUSFS per-target UID hiding

让 **uid 隐藏与路径隐藏都只对指定的应用生效**，而不是全局生效。

面向的场景：检测器（例如春秋 Native Check）会把 PackageManager 的可见性
与 `getpriority(PRIO_USER, uid)` 这类"uid 是否存在"的探针交叉比对。
SUSFS 自带的 `add_hidden_uid` 是**全局**表，隐藏一个包会让所有进程都看不到
它的 uid —— 既会暴露"有东西被隐藏"，也可能把检测器自己的 uid 一起藏掉，
导致整个扫描以 "incomplete" 收场。

本仓库提供内核侧的 per-target 表 + 用户态工具 + 设备脚本，使：

* 隐藏 X 于 A：只有 A 看到 "uid 不存在"
* 隐藏 X 于 A 不影响 B、C
* 目标永远不会"隐藏自己"（除非显式配置）

## 组件

| 位置 | 内容 |
|---|---|
| `patches/patch_susfs_hide_from_uid.py` | sus_path per-target（`0x55554`），内核 + CLI |
| `patches/patch_hide_from_cli_only.py` | 上者的 CLI-only 变体（补 `struct st_susfs_sus_path.uid`） |
| `patches/patch_susfs_hidden_uid.py` | 全局 hidden-uid 表 + `add_hidden_uid`（`0x55555`） |
| `patches/patch_susfs_hidden_uid_from.py` | **per-target** hidden-uid 表（`0x55556`）+ sys.c 钩子重写 + dispatch 注入 |
| `cli/build-cli.sh` | 用 NDK 从 SUSFS 源码重编 `ksu_susfs` |
| `device/hmaoss.sh` | HMA-OSS zygote 资产：开机按 `targets.txt` 成对同步 |
| `device/susfs_sync.sh` | HMA-OSS app 资产：手动同步版本 |
| `device/hma_late_sync.sh` | `service.d` 延迟补跑（CE 解锁后） |
| `.github/workflows/build-ksu-susfs.yml` | CI：拉取指定 SUSFS 版本 → 打补丁 → 编 CLI → 出 artifact |

## 内核侧 ABI

```c
#define CMD_SUSFS_ADD_HIDDEN_UID        0x55555  /* 全局，慎用 */
#define CMD_SUSFS_ADD_HIDDEN_UID_FROM   0x55556  /* per-target */

struct st_susfs_hidden_uid_from { uid_t uid; uid_t target_uid; int err; };
```

`getpriority()` / `setpriority()` 的钩子改成：

```c
if (which == PRIO_USER && who >= 0 &&
    (susfs_uid_is_hidden_from((uid_t)who, current_uid().val) ||
     susfs_uid_is_hidden((uid_t)who)))
        return -ESRCH;
```

细节见 `docs/ARCHITECTURE.md`。

## 快速开始

1. **内核**：在 SUSFS 源码上依次执行

   ```sh
   python3 patches/patch_susfs_hide_from_uid.py   <susfs4ksu_dir>
   python3 patches/patch_susfs_hidden_uid.py      <susfs4ksu_dir>
   python3 patches/patch_susfs_hidden_uid_from.py <susfs4ksu_dir> <kernel_root>
   ```

   第三个脚本必须同时改 **SUSFS 模板**和**已生成的内核树**（`common/include/linux/susfs.h`、
   `common/fs/susfs.c`、`common/include/linux/susfs_def.h`），否则 `kernel/sys.c` 报
   `call to undeclared function 'susfs_uid_is_hidden_from'`。

2. **CLI**：`cli/build-cli.sh`（NDK）会以 CLI-only 模式重打三个补丁并编译
   `ksu_susfs`。**不要用 SUSFS release 里的预编译二进制**，它没有新命令。

3. **设备**：把 `device/hmaoss.sh`、`device/susfs_sync.sh` 放回 HMA-OSS 对应 assets
   重编安装；`device/hma_late_sync.sh` 放 `/data/adb/service.d/`。

4. **验证**

   ```sh
   dmesg | grep CMD_SUSFS_ADD_HIDDEN_UID_FROM | grep -c "target: '<检测器 uid>'"   # 期望 >0
   dmesg | grep -c "CMD_SUSFS_ADD_HIDDEN_UID ->"                                   # 期望 0
   ```

## 已验证环境

| 项 | 版本 |
|---|---|
| 内核 | 6.1.138-android14-11（BakaSU，SUSFS v2.3.0 基线 5192aa2d） |
| SUSFS | simonpunk/susfs4ksu `gki-android14-6.1` |
| HMA-OSS | 5c287a4+8 |
| NDK | 26.0.10792818 |

## 上游更新后

见 **[docs/UPGRADE.md](docs/UPGRADE.md)**：锚点变了会硬失败（`::error::`），按清单逐项复检即可。

## 许可

设备脚本衍生自 **HMA-OSS（AGPL-3.0）**，本仓库整体按 AGPL-3.0 发布；
出处与第三方项目见 `NOTICE.md`。

## 版本锁定与构建产物

| 位置 | 内容 | 锁定方式 |
|---|---|---|
| `hma-oss/` | 隐藏列表模块（HMA-OSS）源码 | **vendored**，版本 = 本仓库 commit |
| `upstream/hma-oss.env` | 来源说明（base commit `5c287a42…`，仅供追溯） | — |
| `upstream/susfs.env` | SUSFS 仓库 + 分支 + commit | commit pin |

当前 SUSFS pin：

```
SUSFS  gki-android14-6.1  5192aa2d33b381b58c1051532f9e1dfa5de6e8d3
```

### 一键产出 APK + 模块 zip

```sh
./scripts/fetch-susfs.sh /tmp/up/susfs          # 按 pin 拉 SUSFS
./cli/build-cli.sh /tmp/up/susfs /tmp/out        # 编 ksu_susfs（三补丁）
./scripts/overlay-device.sh ./hma-oss /tmp/out/ksu_susfs

cd hma-oss && ./gradlew :app:assembleDebug
rm -f zygote/src/main/assets/manager.apk && ./gradlew :zygote:assembleDebug
```

产物：

- `hma-oss/app/build/outputs/apk/debug/*.apk` —— 管理器 APK
- `hma-oss/zygote/build/outputs/magisk/debug/*.zip` —— Zygisk 模块（内含 `manager.apk` 与 `susfs/ksu_susfs`）

GitHub Actions 手动跑 **Build HMA-susfs (APK + Zygisk module)**，可选输入 `susfs_commit` 覆盖 SUSFS pin。

> HMA 的 `versionName/versionCode` 由 git 提交数推导；源码已随本仓库提交，
> 因此版本号稳定可复现，不再依赖上游是否仍有那个 commit。

## 构建分工（重要）

| 产物 | 在哪个仓库构建 | 原因 |
|---|---|---|
| **内核**（0x55554 / 0x55555 / 0x55556） | **`lmnduy/ABK`（魔改版）** | 只有它带 `patches/60_add_per_uid_sus_path.patch`、三个 SUSFS 补丁脚本，以及 `build.yml` 里的补丁步骤与 dispatch 注入 |
| `ksu_susfs` CLI | 本仓库 `cli/build-cli.sh` / 本仓库 CI | 只要 SUSFS 源码 + NDK；也可复用 ABK 的 CLI 产物 |
| 管理器 APK + Zygisk 模块 | 本仓库 `build-hma-susfs.yml` | HMA-OSS 源码已 vendored |

**为什么不能用原作者的 ABK**：上游 ABK 没有这些补丁与步骤，编出来的内核不认识
`0x55554/0x55556`，设备侧脚本会静默跳过 —— 表现为"设了隐藏但 uid 层没生效"。

## 补丁顺序（漏一步就失败）

```sh
./patches/apply-all.sh <susfs_dir>            # 仅 CLI
./patches/apply-all.sh <susfs_dir> <kern_root> # 内核 + CLI
```

1. `60_add_per_uid_sus_path.patch` —— **前置**：给 sus_path 结构加 `allowed_uid`
2. `patch_susfs_hide_from_uid.py` —— 0x55554
3. `patch_susfs_hidden_uid.py` —— 0x55555
4. `patch_susfs_hidden_uid_oracle.py` —— getpriority/setpriority 钩子 + 0x55555 派发（仅内核）
5. `patch_susfs_hidden_uid_from.py` —— 0x55556（含内核树副本 + sys.c 改写 + 派发）

> 第 1 步不能省：少了 `allowed_uid`，第 2 步会报
> `anchor 'st_susfs_sus_path_hlist allowed_uid' matched 0 times`。

## Windows 上跑补丁的坑

`git apply` / `git checkout` 会按 `core.autocrlf` 把文件写回 **CRLF**，而所有补丁锚点都是 `\n`，
于是全部报 "matched 0 times"。`apply-all.sh` 已内置行尾归一化；手工跑时先执行：

```sh
find <susfs_dir> -type f \( -name '*.c' -o -name '*.h' -o -name '*.patch' \) -exec sed -i 's/\r$//' {} +
```

CI（Linux）不受影响。
