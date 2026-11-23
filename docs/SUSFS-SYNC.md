# SUSFS 同步（磁盘层）工作机制

磁盘层（内核 `sus_path`）是**快照式**的，API 层（Zygisk 隐藏）是**实时**的。理解这一点，
几乎能解释所有"PM 里看不到、但 `/data/data` 里还在"的检测报告。

## 数据流

```
HMA-OSS 配置（scope / 模板 / 额外列表）
        │  ConfigManager.getSusfsTargetHides()
        ▼
SusfsSyncer.buildTargetsList()      ← 实时枚举 PackageManager
        │
        ▼  /data/adb/hma_susfs/targets.txt        （快照，只在同步时重写）
        │  + pkgs.txt / extra_paths.txt / sync.sh / enabled
        ▼
sh /data/adb/hma_susfs/sync.sh      （root）
        │  生成 policy.tsv → 一次 supercall 交给内核
        ▼
susfs_load_policy_file()            （内核）建表 + 置位 + 投 loop 队列
```

要点：

- **只有同步会重写 `targets.txt`**。之后无论装了什么新应用，内核的规则都不会改变；
- API 层的 `shouldHide` 每次查询都实时计算，所以新装的包立刻对目标隐藏；
- 两者不一致时，检测器看到的就是「PM 不可见 + 磁盘可见」。

## 什么时候必须同步

| 事件 | 是否影响磁盘层 | 处理 |
|---|---|---|
| 安装/卸载应用 | 是（清单变化） | **同步一次** |
| 修改 scope / 模板 | 是 | 同步（管理器保存时会提示） |
| 重启 | 是（内核规则在内存里） | 模块开机脚本会在 T+120s 自动重放 `targets.txt` |
| 仅修改 API 层开关 | 否 | 无需 |

## 2026-11-23 的两次修正

1. **漏 MT 终端扩展（`bin.mt.termex`）**：`targets.txt` 停在 11-05，包在 11-19 安装 → 清单里没有它，
   内核没有规则；API 层照常隐藏 → Duck 报 `HMA-style concealment`。
   这是**运维问题**：装完应用要同步。
   排查口诀：`stat -c %y targets.txt` 与目标包的安装时间对比。

2. **冷启动同步可能写空清单（已修）**：`buildTargetsList()` 原来只读
   `PackageHelper.packageCache.replayCache`，管理器冷进程时该缓存为空 → 返回空列表 →
   `targets.txt` 被写成 0 字节 → **磁盘层整体失效**。
   - 现在改为实时 `PackageManager.getInstalledPackages(0)` 枚举（replay cache 仅兜底）；
   - `sync()` 增加 `NO_EMPTY_TARGETS_ABK` 守卫：清单为空且同步开启时**拒绝写入**，
     保留上一份可用文件并返回失败信息。

## 云编译

`.github/workflows/build-hma-susfs.yml` 支持 `workflow_dispatch`，一次构建产出：

- `HMA-OSS-main-<hash>-release.apk`（release 版管理器）
- `HMA-OSS-ZYGISK-main-<hash>-release.zip`（Zygisk 模块，内含同一个 `manager.apk`）

注意：CI 使用 runner 自己的 debug 签名，与本机 `adb install -r` 安装过的 APK **签名不同**，
覆盖安装前需先卸载（配置用首页「备份配置 / 还原配置」迁移）。
