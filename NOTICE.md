# 上游来源与署名

本项目是若干开源作品的**组合与补丁集合**。所有原始作品的版权归其作者所有，
本仓库只对"新增的补丁与脚本"主张修改，不对上游作品主张任何权利。

## 1. HMA-OSS —— 隐藏列表模块 / 管理器 App

| 项 | 内容 |
|---|---|
| 作者 | frknkrc44 |
| 上游 | https://github.com/frknkrc44/HMA-OSS |
| 许可 | **AGPL-3.0**（`hma-oss/LICENSE.md` 为上游原文） |
| 本仓库位置 | `hma-oss/`（vendored 源码，未裁剪） |

**基线说明（重要）**：本仓库的 `hma-oss/` 取自 HMA-OSS **oss-173** 发布（上游 tag
`1fe86ce2`，2026-09-30）的快照，另含一个不在上游的本地提交
`5c287a4`（2026-10-14，"Add build watcher helper"）。因此：

- 上游最新的公开节点是 `oss-173` / `1fe86ce2`；
- `5c287a4` 只用于标记我们这份快照的来源，**不是上游 commit**，请勿据此向上游追溯。

**本仓库对该源码的修改**（均可在 `hma-oss/` 内 diff 出来）：

- `zygote/src/main/assets/hmaoss.sh` —— per-target uid 调用（`add_hidden_uid_from`）、
  两遍循环（优先处理检测器 target）、`stat`/CLI 调用的失败容错、开机部署 `ksu_susfs`
- `app/src/main/assets/susfs_sync.sh` —— 手动同步路径的同等改动

依 AGPL-3.0，本仓库整体以 **AGPL-3.0** 发布（根目录 `LICENSE`）。

## 2. SUSFS（susfs4ksu）

| 项 | 内容 |
|---|---|
| 作者 | simonpunk 及贡献者 |
| 上游 | https://gitlab.com/simonpunk/susfs4ksu |
| 许可 | **GPL-2.0** |
| 用法 | 仅作为**构建输入**：clone 到工作目录后打补丁，本仓库不附带其源码副本 |
| 版本 | `gki-android14-6.1` @ `5192aa2d…`，见 `upstream/susfs.env` |

## 3. KernelSU / BakaSU

| 项 | 内容 |
|---|---|
| KernelSU | https://github.com/tiann/KernelSU（GPL-2.0） |
| BakaSU | https://github.com/Baka-SU/BakaSU（GPL-2.0） |
| 用法 | 内核构建时向 `KernelSU/kernel/supercall/dispatch.c` 注入命令分支；本仓库不附带其源码 |

## 4. ABK（Action-Build-Kernel）

- 项目：`lmnduy/ABK`
- 本仓库 `patches/` 中的 `60_add_per_uid_sus_path.patch` 与 `patch_susfs_*.py`
  来自该项目的补丁集；**内核构建仍在 ABK 内完成**，本仓库只负责 CLI / APK / 模块。

## 5. 构建与工具链

- Android NDK（Apache-2.0）
- GitHub Actions：`actions/checkout`、`actions/setup-java`、`actions/upload-artifact`（MIT）
- `nttld/setup-ndk` 已不再使用（改用 runner 预装 NDK）

## 6. 本项目新增的部分（不属于任何上游）

- `CMD_SUSFS_ADD_HIDDEN_UID_FROM = 0x55556` 的 per-target uid 表、
  `susfs_uid_is_hidden_from(uid, caller)`、`ksu_susfs add_hidden_uid_from <uid> <target>`
- `patch_susfs_hidden_uid_from.py`、`patch_hide_from_cli_only.py`、`apply-all.sh`
- `device/hma_late_sync.sh`
- `cli/build-cli.sh`、两个 GitHub Actions 工作流、文档

## 声明

- 本项目不包含任何密钥、证书、账号或个人数据。
- 不保证对任何上游版本的长期兼容；上游改动后补丁会**硬失败**而不是静默产出半成品。
- 如果你是上游作者，希望调整署名方式、补充链接或移除某段衍生内容，请开 issue，
  我们会配合修改。

## 许可

本仓库整体以 **AGPL-3.0** 发布，见根目录 `LICENSE`；`hma-oss/` 内保留上游
`LICENSE.md` 与各文件原有版权头。
