# 故障排查

## "挂载间隙"（Mount gap）反复出现

### 现象

检测器报「挂载间隙」，重启一次后可能消失，也可能依旧；与 HMA-OSS / SUSFS 的
隐藏配置无关（即使关掉全部隐藏也会出现）。

### 判定方法

检测器看的是 **peer-group 连续性**。直接在手机上比对：

```sh
# peer group 应连续；出现 82 -> 200000 这类跳变就是问题
grep -o 'shared:[0-9]*' /proc/self/mountinfo | sed 's/shared://' | sort -n -u | tr '\n' ' '
```

查具体是哪一行造成跳变：

```sh
grep 'shared:200000' /proc/self/mountinfo
# 例：
# 21833 42 0:7 / /dev/kwnwmiad/fsyuzkrq rw,relatime shared:200000 - debugfs debugfs
```

确认属主进程：

```sh
ps -A -o pid,name | awk '$2=="droidspaces"{print}'      # 得到 pid
grep -E 'kwnwmiad|debugfs' /proc/<pid>/mountinfo          # 同一行 → 就是它挂的
```

### 结论（本机实测）

- 该挂载是 **Droidspaces（容器模块）** 在开机阶段创建的 `debugfs`，挂在
  `/dev/<随机>/<随机>`；
- 它的 peer group 是 `200000`，而系统其余挂载是 `shared:1..82` → 82 → 200000 即"间隙"；
- 与 HMA-OSS、SUSFS 的 per-target 隐藏无关（隐藏全关时同样出现）；
- 重启"有时好有时坏"是因为这个挂载与系统挂载存在竞态，组 ID 落点不固定。

验证：`umount /dev/kwnwmiad/<随机>` 后，peer group 立即变为连续（80 81 82），
检测器异常项从 2 条回到 1 条（仅 USB 调试）。

### 处理方式

**方案 A（推荐，若容器不常用）：关闭 Droidspaces 开机自启**

```sh
touch /data/adb/modules/droidspaces/disable   # KernelSU 模块禁用标志
# 需要用时：删除该文件并重启，或在该模块的管理器中启用
rm -f /data/adb/modules/droidspaces/disable
```

**方案 B（保留自启）：开机后卸载该 debugfs**

在 `/data/adb/service.d/` 放一个钩子，开机窗口内 `umount` 掉 `/dev/*` 下的 debugfs；
容器正在使用该挂载时 `umount` 会返回 EBUSY，不会被强拆。缺点是容器再次启动时会重新挂载，
使用期间间隙可能再现。

> 注意：不要全局卸载 `debugfs`（`/sys/kernel/debug` 是系统正常的），只针对
> `/dev/*` 下那个 Droidspaces 的挂载点。

## HMA-OSS 同步失败：does not support per-UID add_sus_path

`sync.sh` 启动时会自检 `add_sus_path <path> <uid>`。若模块里带的 `ksu_susfs`
是旧构建（不含 `[visible_uid]` 参数），会直接 `exit 3`。

- 正确二进制：`build-ksu-susfs` 工作流产物（约 26 KB），help 显示
  `add_sus_path </path> [visible_uid]`；
- 放置位置：`zygote/src/main/assets/susfs/ksu_susfs`（打包后被部署到
  `/data/adb/hma_susfs/bin/` 与 `/data/adb/ksu/bin/`）；
- 权限必须 `0755`。
