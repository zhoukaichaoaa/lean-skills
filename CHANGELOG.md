# Changelog

## 0.17.2 — 2026-07-29

第三方复核报三个生产缺陷，**三条我都先自己复现了，三条都成立**。共同点是同一个：**停靠中途出事时，用户拿不回东西。**

### 1【发布阻断】中途失败会把文件搁浅在没有指针的目录里

状态文件原本在**所有搬运完成之后**才发布。任何中途失败 —— mv 权限错、杀毒软件占句柄、磁盘满、会话被杀、断电 —— 都会留下“文件已搬走、指针没写”的状态。实测：

```
park_rc=1   park: cannot park ghost.txt (already parked: 1)
good.txt_in_worktree=NO      good.txt_inside_park=yes
state_file=ABSENT
restore_rc=1   restore: no parking is open
good.txt_recovered=NO        orphan_park_dirs=1
```

不能靠“die 时回滚已搬的文件”：**崩溃跑不了回滚代码。** 改为**先写意图再做动作** —— 状态在第一次 mv 之前发布。原有的 `.tmp` + `mv` 原子发布写法本身是对的，只是放错了位置。

### 2【高】输入清单不是 NUL 分隔时，park 静默空转而补丁扩散

`[ -s ... ]` 只检查非空、不检查格式。把 `printf '%s\0'` 写成 `printf '%s\n'` 之后：两个 `read -d ''` 循环一次都不执行 → specs 为空 → **xargs 在空输入下照样把命令跑一次**（实测 `printf '' | xargs -0 echo` 会打印且 rc=0）→ 变成无 pathspec 的全树 diff。实测：

```
park_rc=0   state_written=yes   parked_payload=0
patch_bytes=255   patch_names_UNLISTED_other.txt=3
```

park 返回 0、写了状态、什么也没停靠，补丁里却装进了用户从未点名的已修改文件。技能自己的散文里写着这个危险，**警告在散文里，守卫不在代码里**。已加 NUL 终止符校验。

### 3【中】状态与停车区不同步会把用户卡死，且没有写明的出路

状态在、停车区被清掉时，restore 和 park 两边都拒绝，必须手工删状态文件才能继续 —— 而没有任何文档说这件事。两条报错现在都写明出路，并新增一段孤儿停车区文档（里面有什么、怎么取回）。

### 测试判定缺口：两个修复本来都没有验红证据

这才是本轮真正的重点。

**问题 1**：`partial_case` 旧判定只比“状态自洽”（manifest 与磁盘否吻合），**从头到尾没出现过 state 文件，也没尝试过 restore** —— 它在数据无法恢复的状态上打了绿勾，对这次修复完全无感。已升级为：失败的 park 之后**独立进程跑 restore**，断言退出 0、文件逐字节回到工作区、停车区与状态文件都被清掉。

强化后第一次跑就报红，而且**报的不是配方的错** —— `partial_case` 把自己的 `mv` shim 建在**被测仓库里**（`$d/bin`），于是它自己出现在全树快照里。旧判定下无害，因为旧判定根本不看全树。**更强的判定先照出夹具的毛病，这是健康信号。** shim 已移出仓库。

**问题 2**：矩阵里所有输入清单都由 `write_input` 用 `printf '%s\0'` 构造，**没有任何一条用例喂过畸形清单**。所以如果只加一条回滚去删 NUL 校验，那条回滚会 **SURVIVED**。先补矩阵用例（矩阵 40 → 41 例），再加回滚。

### 不造假用例：两道 specs 守卫写明是纵深防御

NUL 校验到位之后，合法输入就不可能产出空 specs、数量也必然相等 —— 这两道守卫在结构上**不可达**。按本仓库处理 `:(top)` 的先例，老实写成“纵深防御，本套件不独立证明它们”并说明为何不可达，而不是塞一条永远不会红的用例。回滚文件里也留了对应说明，免得将来有人当成遗漏去补一条假的。

### run_rollback 支持多对替换

“状态提前发布”是一次**移动**，回滚它需要两处编辑，单条替换表达不了。泛化后每一对仍保留 `t.count(frm) != 1` 的**唯一性断言**，且是对**已被前几对改过的文本**检查 —— 这能顺带抓出“第二对的锚点被第一对破坏”。绝不能降级成“至少匹配一处”：本仓库在锚点上栓过三版。

### 一处账目错误（自记）

汇报 F-2 结果时，我把 NUL 那条回滚的数字拄到了 F-2 那一行，并配了一个与它自身算术矛盾的注脚（“40 passed, 1 failed”合计 41，不可能来自 40 例矩阵）。数字本身是真的，但**它和它的出处对不上，别人就无法复现** —— 和当初提交信息写 38/38、实际 36/38 是同一类。已在 41 例矩阵上重测。

**验证**：本机 Windows 10 + Git Bash。停靠矩阵 **41 passed / 0 failed / 0 skipped**；逐条回滚 **9 条全部 caught，0 SURVIVED，0 skipped**，每条签名合计均为 41；POSIX 安装器矩阵 **21 / 0 / 0**；PowerShell 5.1 安装器矩阵 **28 / 0 / 0**；变异套件 6 条 leg 基线全 rc=0，**35/35 抓到、1 例按平台跳过**。两条新回滚归属唯一：F-2 → 40 passed / 1 failed，唯一 FAIL 是 park fails partway；NUL 校验删除 → 40 passed / 1 failed，唯一 FAIL 是 input list is not NUL-separated。**但九条并非签名互异**：第 6 条（manifest 提前写）与第 7 条（F-2）签名完全相同，都只红 park fails partway，只能靠改动的是配方哪一行来分辨；真正做到单用例唯一归属的是 4 条。macOS 与 Linux 的结果看 CI。

## 0.17.1 — 2026-07-29

**v0.17.0 的停靠配方在 macOS 上根本跑不了。** 三平台 CI 当场报红，macOS 上每一个停靠用例都是 `rc=21 xargs: invalid option -- a`。标签不移动，所以修复走这个新版本。

这是我自己的流程错误：**本机只有 Windows，我把另两个平台完全托给了 CI，却在 CI 跑完之前就打了标签。**

### 两个生产 bug，不是一个

**1. `xargs -a` 是 GNU 扩展**

BSD/macOS 的 xargs 没有 `-a`，直接报错退出。配方在 macOS 上**一步都走不下去**。

**2. 同一行还在拆词 —— 而这一条三个平台都中**

```bash
git diff --binary -- $(tr '\n' ' ' < "$PARK/specs")   # 旧：不加引号的 $(...)
```

shell 按空白拆开它，于是 `:(literal,top)my tracked notes.txt` 被拆成两个参数。`git diff` 又恰好是宽容的（不认识的路径直接忽略），所以**带空格的 tracked 文件会静默地不进补丁**，停靠返回 0，恢复时那份改动就没了。

**为什么 40 个用例一个都没报**：夹具里带空格的路径（`my notes.txt`）**全是 untracked 的**，而 untracked 走的是 `mv`，不过补丁。补丁只管 tracked，而没有一个 tracked 路径带空格 —— 这是一个**夹具盲区**，不是断言弱。已新增 tracked 的 `my tracked notes.txt`，并挂进 `spacepath` 状态。拿 v0.17.0 的配方跑新夹具：**恰好 `spacepath / root` 与 `spacepath / sub` 两条变红**，归属干净。

### 顺手排掉其余不可移植写法

macOS 在那一步就断了，**后面所有 step 都是 skipped** —— 所以不能假设剩下的部分在 macOS 上没问题。干脆把配方里每一处依赖 GNU 行为的地方都换掉：

- `xargs -0 -a FILE` → `while IFS= read -r -d ''` 循环逐条写 NUL，再 `xargs -0 git diff --binary --` 从 stdin 读。全程 NUL，再也不经过拆词。
- `dirname -- "$p"` → `case "$p" in */*) d=${p%/*} ;; *) d=. ;; esac`。**BSD dirname 不收任何选项**，那个本来用来保护 `-draft.txt` 的 `--`，在 macOS 上会变成参数本身。
- `find ... -print -quit` → `find ... -print | head -n 1`。`-quit` 不是每个 find 都有。
- `tr -cd '\0'` → `tr -d -c '\000'`（POSIX 八进制转义）。

### CI 新增一条回归

停靠矩阵现在和安装器矩阵一样，要求**旧版本必须仍然失败**：拿 `v0.17.0` 的 SKILL.md 跑矩阵，能过就报错。断言失去分辨力时会被当场拓出来。

### 又一条只在 macOS 上现形的差异：`mv` 会不会继续找选项

修好可移植性之后，macOS 上停靠矩阵 **40 / 0 / 0** 跑通了，但逐条回滚里“**restore 的 mv 没有 `--`**”那一条 **SURVIVED**（Linux 上被抓）。

原因很精确：**GNU 的 `mv` 会在第一个操作数之后继续扫描选项（permute），BSD/macOS 的不会。** 停靠那条 `mv -- "$p" ...` 里，带短横线的名字是**第 1 个参数**，任何 mv 都会把它当选项 —— 所以两个平台都抓得到；而恢复那条 `mv -- "$PARK/untracked/$p" "$p"` 里它是**第 2 个参数**，排在一个非选项之后，不 permute 的 mv 早就停止解析了。

所以那个 `--` **在 GNU 上是真的在承重**（没它，任何以 `-` 开头的路径在恢复时都会被搞坏），**在 BSD 上则根本构造不出这个向量**。两边都不能擅改：`--` 保留，而回滚用例加一个探针（`mv src -dst` 能否成功），在不 permute 的 mv 上**显式跳过并写明理由**，单独计数，绝不当作“抓到”。汇总行也改成“能跑的都被抓到（N 个跳过）”。

**验证**：停靠矩阵 40 / 0 / 0（Windows 与 macOS 均已实测）；v0.17.0 的配方在新夹具下 38 passed / 2 failed（只红 spacepath 两条）；逐条回滚本机 7/7 全被抓，macOS 上 6 抓 + 1 显式跳过；变异套件 6 条 leg 基线全 rc=0，35/35 抓到、1 例跳过。

## 0.17.0 — 2026-07-29

针对 v0.16.0 的第三方审计。**两条阻断级生产故障，都成立，都打在 0.16.0 刚写进技能的停靠配方上**；顺着根因往下查，我自己又补出三条。外加一批测试可信度问题 —— 其中最难看的一条是：**上一版的停靠矩阵在同一个 shell 里 source 两个配方块，所以那两条生产故障对它完全不可见。**

以下 1、2 是审计报的，3、4、5 是复现过程中自己查出来的。

### 生产故障

**1. `$PARK` 跨不过进程边界**

停靠与恢复是两条独立的 Bash 工具调用，也就是两个进程。配方把停靠区路径存在 shell 变量 `$PARK` 里，恢复那步读到的是空串。实测：`restore_rc=0`，用户文件**不在**工作区，停靠区仍在磁盘上 —— 恢复报告成功而什么都没恢复。加 `set -u` 后直接 `PARK: unbound variable`。

改为**状态落盘**：停靠把目录名写进 `$(git rev-parse --git-dir)/lean-parked.state`，恢复自己重算 git-dir 再读回，且校验读到的是 `lean-parked-*` 形状的**纯基名**（含 `/` 或 `..` 一律拒绝）。恢复不再继承任何东西。

**2. 名字以 `-` 开头的文件让停靠静默失效**

`dirname "$p"` 与 `mv "$p" ...` 遇到 `-draft.txt` 会把它当选项解析。实测停靠返回 0、什么都没停靠，紧接着的 rebase 就卡住。所有 `dirname`/`mv` 补上 `--` 终止符。

**3. `set -e` 在被 source 时不作数**

上面两条能长期潜伏，根因在这里。实测同一个脚本：`bash park.sh` → rc=1，`( . park.sh )` → rc=0。配方原本只靠 `set -e` 兜底。现在每一步都带显式 `|| die "..."`，失败点自己说自己是谁。

**4. 技能降级为用户显式调用**

`resolving-merge-conflicts` 加上 `disable-model-invocation: true`。它驱动一套会动用户未提交工作的破坏性流程，不该由模型读一段 description 自行决定要不要用。常驻技能因此从 5 个减到 4 个，两份 manifest 的描述、安装器横幅、CI 的常驻集断言同步更新。

**5. 一处遗漏的 `:(top)`**

第 4 步那条 `git restore --staged` 只写了 `:(top)`，没写 `literal`。status 会打印 `a[1].txt` 这类名字，而 git 的 pathspec **既按字面匹配也按通配匹配**，实测：

```
git restore --staged -- ':(top)a[1].txt'   ->  rc=0，a1.txt 和 a[1].txt 一起被取消暂存
```

用户点名的那个确实处理了，但**没点名的 `a1.txt` 也被一起动了，退出码 0，一声不吭**。已改为 `:(literal,top)`，CI 的断言也从"必须有 `:(top)`"收紧为"必须有 `:(literal,top)`"。

### 测试可信度

**矩阵曾在同一个 shell 里跑完整个往返**，所以两个配方块之间的所有状态传递都"能用"。现在停靠、`rebase --continue`、恢复分在**三段互不传递状态**的执行里：停靠在子 shell 里 source（这比生产更严苛 —— `set -e` 在被 source 时不作数，配方必须靠自己的 `|| die` 站住），恢复则用 `env -u PARK -u PARK_NAME -u G -u STATE bash restore.sh` 独立启动，继承的可能性被显式掐掉。仅此一项改动就让上面第 1 条立刻变红。停靠矩阵 40 例，0 跳过。

**补回一条被错误放弃的回滚用例，而且是第二次才补对**。上一版在逐条回滚里写着"`:(literal)` 在本平台没有诚实的用例"，理由是 `b*c.txt` 这种名字 NTFS 存不了。那个理由**过度推广了** —— 站不住的只有星号，`a[1].txt` 各平台都合法。

但我第一次补的用例**自己没通过审**：回滚跑完是 `SURVIVED`。原因是诱饵 `a1.txt` 当时是死的。想清楚才发现条件很窄 —— 第 4 步的清单只排除两类路径：**只暂存了的**（工作区和索引已经一致，glob 扫到也不改变什么）和**冲突中的**。所以 `literal` 唯一能起作用的场合，是一个**冲突中的文件**的名字被某个停靠路径当 glob 匹配到。实测（a1.txt 未解决，a[1].txt 带用户改动）：

```
git checkout -- ':(literal,top)a[1].txt'   ->  rc=0，a1.txt 仍是三个 stage
git checkout -- ':(top)a[1].txt'           ->  error: path 'a1.txt' is unmerged, rc=1
```

**所以它是 pathspec 陷阱的又一次**：不是悄悄改错文件，而是整条命令被拒，停靠当场停住，用户的改动既没停靠也没安全。用例改为按这个形状单独构造（不走共用状态机，不影响其余用例），逐条回滚 6 → 7 项，停靠矩阵 39 → 40 例。

**变异套件此前没有基线**，而这是本轮最严重的一处自欺。"变异被抓"这个推断，只有在**未变异时该 leg 是绿的**才成立。加上基线检查后，当时五条 leg 里**有三条在未变异时就是红的**：

- `meta` leg 在本机**一直是 rc=127**。harness 把 `sys.executable` 直接写进 bash 脚本，Windows 路径的反斜杠被 shell 吃掉，`F:\python\python.exe` 变成命令 `F:pythonpython.exe`，命令不存在。
- `rec` leg 是 rc=1，因为 CI 里还断言着重写前的 `git checkout -- ":(top)$p"`。
- `sh` leg 是 rc=1，因为 Git Bash 建不出那个断裂链接。

也就是说上一版"36/36 全抓"里，**大部分是白捡的** —— leg 本来就是红的，变不变异都红。三条全部修好、基线全绿之后重跑，立刻掉出两个真正的幸存者：

- **`installer: rollback only restores directories` 幸存**。这正是 0.13.2 那个丢数据的 bug（回滚用 `-d` 判定，`--adopt` 接管的普通文件和断裂链接因此跳过回滚，随后被 `rm -rf` 删掉）。原因是它被挂在 CI 的 `install.sh` leg 上，而那条 leg 的故障注入**只用目录当占位者**，看不见这个向量。已改挂到 `install_matrix.sh` 那条 leg（它会逐个用 dir/file/link/broken 当占位者），改挂后立刻被抓。为此把 CI 里"停靠与安装器矩阵"一步拆成两步，故障归属也更清楚。
- **`installer: drive letters absolute everywhere again` 幸存**，但这条**不是测试的问题**：该变异把 `MINGW*|MSYS*|CYGWIN*)` 扩成 `|*)`，而本机 `uname -s` 就是 `MINGW64_NT-*`，第一个分支本来就匹配 —— 这个向量在 Windows 上**按构造不可能被杀死**。把它记成"抓到"是往好听方向撒谎，记成"幸存"又是往难听方向。新增 `@posix` 平台限定，本机报**跳过并说明原因**，留给 Linux/macOS 的 CI 去杀。

另外 `NO_SYMLINKS` 那段"Git Bash 不支持符号链接所以本地删掉这几行"是**删掉了覆盖而不是删掉障碍** —— 实测 `MSYS=winsymlinks:nativestrict` 下 Git Bash 能建真链接，整条 leg 不删任何行也是绿的。改为设环境变量，本地跑的和 CI 跑的是同一份脚本。

**跳过不再折进通过数**。两套安装器矩阵与变异套件现在都分开报告 passed/failed/skipped。此前 POSIX 矩阵只打印 "N passed, M failed"，跳过的用例混在里面看不出来。CI 断言 Linux/macOS 上停靠矩阵必须 `40 passed, 0 failed, 0 skipped`（这两个平台能存 newline 和 tab，也能建链接，跳过只可能意味着探针坏了），安装器矩阵必须 `21 passed, 0 failed, 0 skipped`。**光有总数还不够** —— 数目对得上而某个用例悄悄变成另一个简单用例的副本，是同一类骗局；所以另加一条按名字点名的断言：`newlinepath`/`tabpath`/`globpath`/`spacepath`/`dashpath`/`utf8path`/`symlink`/`brokenlink`/`linkmixed` 各自的 `/ root` 与 `/ sub` 共 18 行必须逐行出现在输出里。

顺带删掉一个用不上的探针：矩阵里曾有个 `b*c.txt` 的诱饵和一个探测它能否落盘的 `STAR_OK`，而 NTFS 根本存不了 `*`（MSYS 会替换成私用区字符，于是 shell 写下的名字和磁盘上的字节对不上，git 永远找不到那个文件），于是那组用例在 Windows 上只能跳过。`b*c.txt` 与探针一并删掉；`literal` 的行为证据由上面那个冲突诱饵用例承担，它三个平台都能跑。

**PowerShell 走双解释器**。Windows PowerShell 5.1 与 pwsh 7 在原生命令重定向、`-LiteralPath`、以及断裂链接下 `Test-Path` 的回答上都不同，安装器对两者的用户都发货。CI 现在对 `powershell` 和 `pwsh` 各跑一遍矩阵（各断言 `28 passed, 0 failed, 0 skipped`），并各自要求 v0.12.0 仍然失败。

**PowerShell 的符号链接探针一直在静默跳过 7 个用例**。探针用"指向一个不存在的目标"建链接来试探能力，而 5.1 恰恰**拒绝**创建指向不存在目标的链接 —— 于是在符号链接完全可用的机器上，探针也报告"不支持"。修正为先建目标再建链接。7 个用例真正跑起来之后全绿，另加一个 junction 占位者用例（Windows 上常见，且不需要符号链接权限）。

### 更正：0.13.3 关于 `Test-Path` 的说法是错的

0.13.3 写道 `Test-Path` "同样回答的是链接目标是否存在，断裂链接返回 False"，并据此给 `install.ps1` 加了 `Test-Exists`。

**实测（Windows PowerShell 5.1.19041.6456）：对断裂的符号链接，`Test-Path` 与 `Test-Path -LiteralPath` 都返回 `True`。** 那句话不成立，因此那次改动的**理由是错的**。

修好探针、让 7 个符号链接用例真正执行之后，**v0.13.2（即加 `Test-Exists` 之前的版本）在矩阵上是 28/28 全过**。也就是说 `Test-Exists` 没有修好任何可观测的行为差异。

保留它，不回滚，理由只有一条且不再夸大：它比 `Test-Path` 少依赖一层对链接语义的假设。但它**不是**一次 bug 修复，0.13.3 把它记成 bug 修复是错的。pwsh 7 的行为本机无法验证（未安装），已交给 CI 的 pwsh leg 去测。

### 交付说明

新增 [`SIGNING.md`](SIGNING.md)：公钥、`allowed_signers` 用法，以及**签名能证明什么、不能证明什么** —— 这把密钥只登记为仓库级 deploy key，没有登记为账号级 signing key，所以 GitHub 不显示 Verified、API 也查不到它，"密钥属于谁"目前只有仓库内的声明这一个来源。要取得可独立核验的身份绑定需要仓库所有者在账号设置里额外登记同一把公钥为 Signing Key。

**不再公布 codeload 压缩包的 SHA-256。** 那些包由 GitHub 实时生成，字节不保证稳定，第三方核不出来。改为公布 tag/commit/tree 三个 git 对象哈希，并给出一条参数写全的 `git archive`（含 `gzip -n`）供需要固定归档的人自行复现。

**验证**（本机 Windows 10 + Git Bash，`MSYS=winsymlinks:nativestrict`）：停靠矩阵 **40 passed / 0 failed / 0 skipped**，且 18 个难名字用例逐行点名核对；POSIX 安装器矩阵 **21 / 0 / 0**；PowerShell 5.1 安装器矩阵 **28 / 0 / 0**，v0.12.0 在同一矩阵上仍然 4 项失败（判别力还在）；逐条回滚 **7 项全部被抓**，且七条的失败签名互不相同（3/37、3/37、38/2、38/2、39/1、39/1、38/2），说明它们测的是不同的东西而不是同一条断言的七个副本；变异套件 **6 条 leg 基线全 rc=0**，36 例中 **35/35 抓到、1 例按平台跳过并写明原因**。

**本机没验到的**：pwsh 7（未安装）—— 双解释器那条腿只在 CI 上跑；Linux/macOS 的所有断言同理。这两句是限度声明，不是免责声明：CI 红了就是没过。

## 0.16.0 — 2026-07-29

自审，专打上一版交付的两套矩阵本身。**三条，都是我自己写的盲区。**

**1. 安装器矩阵里有一个定义了但从未调用的注入分支**

`inject_case` 支持 `aside`（旧目标移出失败）与 `inplace`（新目标换入失败）两个阶段，而我只调用了 `inplace`。审计方明确要求“旧目标移出、新目标换入各阶段故障注入”，而我交了一半。已补上，POSIX 矩阵从 18 到 21。

**2. 两套矩阵都没有含空格/非 ASCII 的路径**

而技能本身花了一整段讲引号与转义。已新增 `spacepath` / `utf8path` 两种状态（各跑根目录与子目录），实测通过。另加一个 `newlinepath`，**带可行性探测** —— NTFS 存不下真换行，MSYS 会把它替换成私有区字符（`U+F00A`），所以本机显式 skip，不假装测过。

**3. PowerShell 安装器根本没有矩阵 —— 而我补的第一版分辨不出任何版本**

`tests/install_matrix.ps1` 按与 POSIX 侧同样的标准写：跑真脚本、断言退出码与整棵树（类型/哈希/链接目标）、两个换位阶段各自注入 `Move-Item` 失败。

但第一版跑 v0.12.0 / v0.13.2 / v0.13.3 **全部 14/14 通过** —— 它分辨不出任何版本差异，因为差异只存在于符号链接路径（本机无权限）和拒绝退出码（我没测）。**一个分辨不出任何版本的矩阵是弱证据。** 补上拒绝退出码维度后：

| 版本 | 结果 |
|---|---|
| v0.12.0 | **15 passed, 4 failed**（相对路径 / 盘符相对 / 目标=源 / 未知选项，当时都是 `throw`→exit 1） |
| v0.13.2 | 19/19 —— 与当前的差异只在符号链接，**本机分辨不了**，靠 CI 的 Windows runner（以管理员运行） |
| 当前 | 19/19 |

CI 的 Windows 腿现在跑这套矩阵，**并断言 v0.12.0 必须不通过**。

**一条探针自身的错误**：我写的路径形状探针把 `park.sh` source 了两次（一次在子 shell），文件系统改动会残留，头一轮报的两个 FAIL 是探针自己的 bug 而不是配方的。修掉后三种路径形状全通。

**第四条，在接 CI 时发现**：新加的拒绝类用例从仓库根跑，而旧版会**接受** `C:relative-target` 并在当前目录建出 `relative-target/` —— 于是 RED 那一跑把垃圾留在了被测仓库里，Windows 腿的“repo dirty”断言抦下了它。拒绝类用例现在在沙盒目录里跑。**一个会污染被测对象的测试，结论不可信。**

**另两条转运层造成的**：CI 里的 `.	ests\...` 被转义成了制表符（改用正斜杠）；以及第三次撞上 PowerShell 5.1 对原生命令 stderr 的 `NativeCommandError`（调用前降为 `Continue`）。

**验证**：停靠矩阵 27/27；POSIX 安装器矩阵 21/21；PowerShell 安装器矩阵 19/19；回滚 6/6 全红；变异 36/36。

## 0.15.0 — 2026-07-28

**未跟踪符号链接在恢复时被静默删除**（已复现）

恢复逻辑用 `find . -type f` 重新枚举停靠内容 —— 而符号链接是 `-type l`。它会被 `mv` 进停靠区，恢复时找不到，然后连同停靠区一起被 `rm -rf`，**而整块返回 0**：

```
symlink_parked_before_restore=1
symlink_present_after_restore=0
parking_area_present_after_restore=0
exit=0
```

（本机 Git Bash 默认把 `ln -s` 做成副本，设 `MSYS=winsymlinks:nativestrict` 后能造出真链接，因此这条本机完整复现。）

改为**停靠时写 NUL 分隔清单，恢复严格按清单逐项处理**；删除停靠区前额外确认它已**不含任何非目录项**（`! -type d`）—— 即使清单漏了东西，也不会变成一次删除。

**停靠矩阵扩到 23 个**：新增 `symlink` / `brokenlink` / `linkmixed` 三种状态（各跑根目录与子目录）；snapshot 不再只比普通文件哈希，而是比**类型 + 内容/readlink 目标 + 权限**。平台造不出真链接时这三组显式 skip，不静默变成测普通文件。

**回滚套件 6 项全红**，新增“恢复改用 `find -type f` 重扫”一项。另一项“去掉残留守卫”我**没有当作用例** —— 清单正确时它不可能失败，和 `:(top)` 同形，写了也只是凑数。

**安装器状态矩阵**（`tests/install_matrix.sh`，18 个用例，跑真脚本）

fresh install / managed upgrade / uninstall；目标分别为目录、普通文件、符号链接、断裂链接；无 marker 默认保留（exit 3）与 `--adopt` 明确接管；换入阶段注入 `mv` 失败。断言包括退出码、**整棵树的类型/哈希/权限/链接目标**、以及无 staging/outgoing 残留。

**历史 RED 精确对得上**：

| 版本 | 失败用例 | 对应缺陷 |
|---|---|---|
| v0.12.0 | 3 个断裂链接 + `file` 换入失败 | 尚无 symlink 感知；回滚判定 `[ -d ]` |
| v0.13.1 | 仅 `file` / `broken` 换入失败 2 条 | symlink 已纳入，回滚仍 `[ -d ]` |
| 当前 | 无 | — |

CI 不只跑当前矩阵，还**断言 v0.12.0 与 v0.13.1 必须不通过** —— 否则说明矩阵已经测不出东西了。

**验证**：停靠矩阵 23/23；安装器矩阵 18/18；回滚 6/6 全红；变异 36/36；CI 10 条 run-step 里 9 条在干净克隆上实跑（含 Windows）。

**一处更正**：本版首次提交的信息里写的是“变异 38/38”，**那是错的** —— 我在它跑完前就提交了，实际是 36/38。两个存活用例的锚点串如今在技能里出现两次，而变异只替换第一处，所以它们永远不可能失败；两者均与回滚套件重叠，已删除。

## 0.14.0 — 2026-07-28

审计方不判定 v0.13.5 闭合，要求：不可变交付标识、**规则是否统一覆盖**而非再查两个实例、真实的 RED→GREEN、以及“测试驱动真配方而非匹配文档文字”。都接受。

**配方改为可执行，测试直接跑它**

`SKILL.md` 里的停靠与恢复两个代码块不再是带 `<占位符>` 的伪代码，而是标记为 "
"`# lean-skills:park` / `# lean-skills:restore` 的可运行 shell，参数通过 `$TRACKED` / `$UNTRACKED` 传入。"
"`tests/parking_matrix.sh` 从文档里**抽出这两个块并执行** —— 文档写错，测试就红；测试不再可能靠匹配措辞通过，也不是规则的第二份实现。

**状态矩阵**（每个用例独立进程、独立退出码）：tracked / staged / deleted / renamed / untracked-only / mixed / none / clash，每种**分别在仓库根和子目录下各跑一遍**，加一个停靠后放弃（`--abort`）的用例，共 17 个。通过条件是**字节级**：rebase 跑完后工作区、index、untracked 文件的 porcelain 与每个文件的 blob 哈希都要与停靠前一致。

**这个矩阵当场又拓出一个真缺陷**：恢复块的最后一行是裸 `&&` 链，碰撞场景下整块返回非零（`rc=24`） —— 而碰撞是**设计内的结果**，不该表现为“恢复失败”。已改为显式 `if`。

**逐条回滚**（`tests/parking_rollback.sh`）：把每一项修复单独回滚到文档副本上，矩阵必须变红。五项全部被抓：

| 回滚 | 破的用例 |
|---|---|
| 去掉 `cd` 到工作区根 | 4 个子目录用例 |
| 去掉空补丁守卫 | untracked-only 两个 |
| 不停靠 untracked 侧 | clash 两个（rebase 跑不完） |
| 单条命令传全部路径取消暂存 | 4 个 |
| 去掉换回时的碰撞守卫 | clash 两个 |

**两条我不声称的事**：

- **`:(top)` 在有 `cd` 的前提下是冗余保险**，单独去掉它不会红。本套测试**没有独立证明它** —— 一个不可能失败的用例什么也证明不了，所以我删掉了那个重复用例而不是留着凑数。
- **与 v0.13.4 的横向对比不精确**：那一版的块尚不可执行，harness 会直接跳过停靠（4 passed / 12 failed），那 12 个失败来自“根本没停靠”而非隔离到具体修复。**真正的隔离是上面那张回滚表。**

**CI** 新增一步，在 Linux 与 macOS 两条腿上跑矩阵与回滚。

**定位**：`resolving-merge-conflicts` 按审计要求标为 **experimental**（README 与技能 frontmatter 均标注）。

**变异套件减了 4 个**：配方改成可执行形态后，那四个文本锚点用例失效。它们测的性质现在由 `parking_rollback.sh` 用**行为证据**覆盖（文本锚点只能说“命令还在”，回滚说的是“没有它流程就坏”）。删掉而不是重新锚定凑数。

**验证**：矩阵 17/17；回滚 5/5 全部变红；`tests/mutations.py` 38/38；CI 的 10 条 run-step 里 9 条在干净克隆上实跑（含 Windows）。

## 0.13.5 — 2026-07-28

第八份审计，2 条，都成立。

**从子目录执行时，所有路径都解析错**

`git status --porcelain` 打印的是**仓库根相对**路径，而 `git restore`、`git diff`、`git checkout`、`mv` 全部按**当前目录**解析。在 `repo/sub` 里处理 `repo/user.txt` 的冲突：

```
git restore --staged -- user.txt   exit=1  pathspec did not match
  索引里还在: [f.txt user.txt]        <- 用户的修改没被救出来
git diff --binary -- user.txt      exit=0  补丁 0 字节   <- 退出码 0，什么也没捕获
git checkout -- user.txt           exit=1
```

中间那行正是本技能开篇命名的**“塔成空”** —— 出现在我自己的配方里。而第 9 步早在 0.10.0 就用上了 `:(top)`，我当时只修了那一处，没把同样的道理用到第 3、4、8 步 —— 又是“修实例不修规则”。

新增**第 0 步：先站到工作区顶部**（`cd "$(git rev-parse --show-toplevel)"`），并给每一条吃路径的命令加 `:(top)`。两道都要：`mv` / `mkdir` 不接受 pathspec，只能靠 `cd`。

**只有 untracked 文件时，恢复阶段必失败**

这时补丁是 0 字节，而配方照样 `git apply --3way`：

```
git apply --3way <空补丁>   exit=128
error: No valid patches in input (allow with "--allow-empty")
```

技能把非零退出码读成“操作也改了这些路径，有冲突”，于是报一个**不存在的冲突**、停靠区也不会被清理。现在先判 `test -s`，空就直接进 untracked 恢复。

**顺带**：拆分停靠名单时明确“只拆第 4 步那份名单” —— 直接拿 `git status` 全部输出会把刚暂存的冲突文件也包进去。

**CI** 新增三条：每个吃路径的配方必须带 `:(top)`；空补丁守卫不得消失；技能必须先回工作区顶部。

**变异锚点改为自动推导**：连续三版都有用例因为配方改了措辞而变成 SETUP 失败，其中一个还静默锚到了提及该命令的**散文句子**。现在用 `code_line(文件, 命令开头)` 从文件里取唯一匹配的**代码行**（匹配不到或多于一条直接报错）。用例关心的是“这条命令还在不在”，不是它周围的措辞。

**验证**：CI 的 9 条 run-step 里 8 条在干净克隆上实跑（含 Windows）；`tests/mutations.py` 42/42。

## 0.13.4 — 2026-07-28

第七份第三方审计，2 条，**都成立**。两条都打在 0.13.3 刚写的停靠流程上，而第二条是同一个陷阱的**第四次** —— 就在我宣布“把规则写下来”的那一版里。

**“untracked 不挡 `--continue`”只对当前那个提交成立**

后续提交如果要创建一个当前 untracked 的路径，git 会停下：

```
rebase --continue exit=1
error: The following untracked working tree files would be overwritten by merge
还在 rebase? yes
```

重命名正是最容易撞上的形状 —— 新路径是 untracked，而操作本身也可能在创建它。改为**两侧都停靠**：tracked 走补丁，untracked 连目录结构一起移出工作区。

**`git restore --staged` 拿到整份名单，里面含 untracked 路径**

```
git restore --staged -- a.txt b.txt   exit=1
error: pathspec 'b.txt' did not match any file(s) known to git
恢复后: [D  a.txt ...]      <- 删除仍在暂存区
```

这是 **`git restore --staged` → `git stash push` → `git checkout --` → `git restore --staged`** 同一个陷阱的第四次。改为只对 `git diff --cached --name-only` 实际列出的路径取消暂存。技能里现在写的是规则本身，并把四次实例列出来。

**我自己又挖出的两条**

- **没有在途工作时，`git diff --binary --` 不带路径就 diff 整棵树** —— 补丁会把刚暂存的冲突解决一并装进去，正是 `git stash` 那个形状。实测空列表下补丁 159 字节。现在明写：无在途工作就整步跳过。
- **untracked 移回去时会静默覆盖操作创建的同名文件**。加碰撞守卫：路径已被占用就拒绝覆盖，保留停靠区并同时告知两边。

**第 9 步也修了**：它之前只查路径还在不在，查不出“回来时变成了已暂存”。现在要求比对 porcelain 的**前两个字符**，不只是名字。

**四种形状实测**（重命名+子目录新文件 / 后续提交同名碰撞 / 仅 tracked 修改 / 无在途工作）：前三种最终状态与第 4 步逐字符一致，碰撞那种 rebase 能跑完（旧版卡死）且拒绝覆盖。

**变异用例又错了一次**：重锚脚本取“第一个包含该字符串的行”，而重写后那个字符串先出现在**散文**里 —— 于是两个用例改的是散文句子，代码块断言当然不会报警（报 37/39）。已改为只锚代码行。**变异测试的锚点本身也需要被审。**

**退休规则收窄**：`diff --cached --name-only` 这条退休模式与本版新增的合法用法撞车（前者退休的是第 3 步里丢重命名的那个形式）。收窄为带 `HEAD` 的形式，并**新增一个变异用例证明它仍能抓到真回归** —— 不能为了让自己的代码过关而削弱守卫。

**验证**：CI 的 9 条 run-step 里 8 条在干净克隆上实跑（含 Windows）；`tests/mutations.py` 39/39。

## 0.13.3 — 2026-07-28

自审，专打 0.13.2 刚写的停靠流程。**两条，一条是同一个陷阱第三次换命令咬我，一条是我自己违反双平台规则。**

**`git checkout --` 遇到它不认识的路径会整条失败**

用户在途做的是一次重命名时，第 4 步之后新路径是 untracked、旧路径的删除是 tracked：

```
step 4 后: [UU f.txt  D sub/old.txt ?? sub/new.txt ]
git checkout -- sub/old.txt sub/new.txt
error: pathspec 'sub/new.txt' did not match any file(s) known to git   exit=1
清理后: [M  f.txt  D sub/old.txt ...]      <- 删除没被清掉，--continue 会拒绝
```

这是 **`git restore --staged` → `git stash push` → `git checkout --`** 同一个陷阱的第三次。真正的教训已写进技能：**任何吃 pathspec 的 git 命令，遇到一个它不认识的路径就拒绝整条命令**。改为 `git checkout --` 只给 tracked 的那些（untracked 本来就不挡 `--continue`、也不会被提交）；`git diff` 是宽容的，补丁那条可以全部点名。修正后同一夹具：`checkout exit=0`，最终状态 ` D sub/old.txt` + `?? sub/new.txt`（正是第 4 步的形状），0 次被卷进提交。

**中途 `--abort` 会让停靠的工作看起来消失**

`git rebase --abort` 把工作区恢复到 rebase 之前 —— 也就是停靠之前，用户的修改在工作区里不见了，只在补丁里。实测补丁能完整重新应用，但技能此前对这个分支一字未提。已补上。

**Windows 侧的 symlink 盲区根本没修**

0.13.1 把 `[ -e ]` 改成 `exists()`（`-e` 或 `-L`）—— **只改了 `install.sh`**。`install.ps1` 仍在用 `Test-Path`，而它同样回答的是链接**目标**是否存在，断裂链接返回 False。同一个 bug 在 Windows 侧原封不动地留了一版 —— 直接违反了“改动要双平台都做”这条规则。新增 `Test-Exists`（先 `Test-Path`，不行则查父目录的条目），6 处 `$target` 判定与回滚全部改用它。CI 新增一条：`install.ps1` 里不得再用 `Test-Path` 决定用户的东西。

**本机无法验证**：Windows 上创建断裂符号链接需要管理员或开发者模式，本机造不出。`Test-Exists` 的正确性靠代码路径与 CI；上面那条文本断言至少保证它不会静默退回。

> **0.17.0 更正**：上面这一整段的前提是错的。实测 5.1 对断裂链接 `Test-Path` 返回 **True**，不是 False；探针修好后 v0.13.2 在矩阵上 28/28 全过，`Test-Exists` 没有修好任何可观测差异。详见 0.17.0 那一节。

**验证**：CI 的 9 条 run-step 里 8 条在干净克隆上实跑（含 Windows）；`tests/mutations.py` 36/36。

## 0.13.2 — 2026-07-28

第六份第三方审计，2 条发现，**都成立，都是丢数据**。两条打的都是 0.13.1 自己刚写的代码。

**`--adopt` 接管非目录时，回滚会把用户的东西删掉**

0.11.0 加的回滚判定是 `[ -d "$_outgoing" ]`。`--adopt` 可以接管的不只是目录 —— 也可能是普通文件或断裂的符号链接（0.13.1 刚把后者纳入保护）。这些被挪到 `outgoing` 之后，`-d` 为假，于是回滚分支不进，紧接着的 `rm -rf` 把它删了。

故障注入（PATH 上垫假 `mv`，让换位失败），目标是用户自己的一个普通文件：

```
安装前: tdd 是 普通文件，内容=[THE USERS OWN FILE, NOT A DIRECTORY]
注入失败后 exit=1
>>> tdd 已消失 —— 用户的文件被销毁
残留 outgoing: []
```

改为 `exists "$_outgoing"`（`-e` 或 `-L`）。同一注入后：`tdd 还在: 文件`，内容原样，脚本打印 `restored tdd`。

**`cp` 停靠不住"改动"，它只搬得动"内容"**

0.13.1 把 rebase 的停靠从 `git stash` 换成 `cp` 到 `.git/lean-parked/`。审计指出五个问题，逐条复现：

```
$ cp a/config.txt b/config.txt doomed.txt later.txt "$P/"
cp: will not overwrite just-created '.git/lean-parked/config.txt' with 'b/config.txt'
exit=1
停靠目录内容: [config.txt later.txt]     <- 两个 config.txt 只剩一份
```

- **删除的文件**没有内容可复制，`cp` 整条失败
- **不同目录的同名文件**在扁平目录里互相覆盖
- **重命名**是两个路径，复制表达不了
- **文件模式**丢失
- **固定的目录名**会和上一次未完成运行的残留混用
- 恢复时直接覆盖，会把 **rebase 后续提交对同一文件的改动**抹掉

改用 `git diff --binary` 生成补丁、`git apply --3way` 恢复。同一夹具（用户改了 `a/config.txt`、`b/config.txt`，删了 `doomed.txt`，改了一个 rebase 后续提交也会改的 `later.txt`）：

```
a/config.txt=[AA]  b/config.txt=[BB]   <- 无碰撞
doomed.txt 已删除（正确）
later.txt=[<<<<<<< ours]               <- 冲突标记，而不是静默覆盖
status=[... UU later.txt]
```

`git apply --3way` 在这里的价值正是最后一条：`cp` 会把 rebase 的版本直接盖掉，补丁则把分歧摆出来交给用户。干净恢复时 `git restore --staged` 能精确还原第 4 步留下的未暂存状态（` M` / ` D`），二进制文件往返哈希一致。补丁文件名改为带时间戳且**存在即拒绝**。

**CI**：技能正文的代码块里不得再出现 `git stash` 或 `cp` 作为停靠手段；配方锚点加 `git diff --binary --` 与 `git apply --3way`。`tests/mutations.py` 增至 34 个。

**本机无法验证的**：文件模式变更的往返 —— Windows 上 `core.fileMode` 默认为假，`chmod -x` 不会出现在 diff 里。这条依赖 CI 的两条 POSIX 腿。

**变异用例自身也会陈旧**：本次改动后，3 个旧用例因为锚点指向的代码已被改写而失效（回滚判定、绝对路径守卫、`stash push -u`）。harness 把 SETUP 失败计为未通过（先报 31/34），所以它们不会静默变成哑弹 —— 已重新锚定，并把已过时的 stash 用例换成“不得重新用 stash 停靠”这条新契约。

**验证**：CI 的 9 条 run-step 里 8 条在干净克隆上实跑（含 Windows）；`tests/mutations.py` 34/34。

## 0.13.1 — 2026-07-28

第五份第三方审计，5 条发现。**4 条成立**，1 条只对了一半；另外我在复现过程中发现问题比审计描述的更深，最后的修法和它建议的不一样。

**多提交 rebase 连续冲突时，停靠的工作取不回来（P1）**

夹具：被 rebase 的分支有两个提交、都冲突。按 0.12.0 写的流程 `stash push → rebase --continue → stash pop`：

```
rebase --continue exit=1        # 停在第二个冲突，索引是 UU
git stash pop     exit=1        # error: could not write index
user.txt 恢复了吗: NO
```

**但审计建议的修法我也验失败了** —— 记住 stash 的 OID、等 rebase 全部结束再 `apply`，同样 exit=1。继续挖才看清根因：

```
git stash push -- tracked.txt   # 只点名一个文件
git stash show --name-only      # [f.txt tracked.txt]   <- 冲突解决也进去了
```

**`git stash` 在这里根本是错的工具**：stash 总会记录**整个索引**，而冲突进行中的索引里装着你刚暂存的冲突解决。等 rebase 结束再 pop，它会把那份**过期的解决**重放到已经 rebase 过的文件上，凭空造出一个 `UU` 冲突；而且文件回来是**已暂存**状态，不是第 4 步留下的未暂存状态。

改为不碰索引：把内容复制到 `.git/lean-parked/`，`git checkout --` 清干净工作区，整个 rebase 结束后再复制回去。同一夹具对比：

| | 停靠方式 | 取回后 status | 额外冲突 |
|---|---|---|---|
| 旧 | `git stash` | `UU f.txt` + `M  tracked.txt`（已暂存） | 有 |
| 新 | 复制到 `.git` 下 | ` M tracked.txt`（未暂存，正确） | 无 |

**顺带纠正 0.12.0 自己的一个误判**：那一版给 `stash push` 加 `-u`，理由是"第 4 步之后新文件变成 untracked，裸 push 会整条失败"。实测 **untracked 文件根本不挡 `rebase --continue`，也不会被它提交** —— 当初就不该把它们停靠。现在只停靠 tracked 的未暂存修改。

**root commit 冲突时 `^<n>` 不存在（#5）**

`git rebase --root` 让 root commit 冲突时，`REBASE_HEAD` 正确指向它，但它没有父提交，`REBASE_HEAD^1` **exit 128**，技能算不出这次操作带来了什么。改为先 `git rev-list --parents -n 1 <REF>` 数父提交：0 个用空树、1 个用 `^1`、多个要问用户 `-m`。

**Windows 安装器接受驱动器相对路径（#2）**

`[IO.Path]::IsPathRooted()` 不是"是否绝对路径"：

```
C:relative-target   rooted=True     GetFullPath -> C:\relative-target
\single-leading     rooted=True
```

前者相对于**进程在 C 盘的当前目录**，后者相对于**当前驱动器** —— 都不是调用者指定的位置。改为要求"盘符 + 分隔符"或合法 UNC。

**POSIX 安装器把 Windows 路径当绝对路径（#3，半条成立）**

`C:/skills` 在 Git Bash / MSYS / Cygwin 下确实是绝对路径，在 Linux/macOS 下是**相对路径**，会在当前目录建出一个名叫 `C:` 的目录。改为用 `uname -s` 判平台，非 Windows 环境只接受以 `/` 开头的路径。

审计还说 `C:relative` 也被接受 —— **这半句不成立**，实测 exit=2。shell 的 `case` 模式里 `[\\/]` 是一个字符类而不是"零或多个"，分隔符本来就是必需的。

**断裂的 symlink 会被覆盖（#4）**

`[ -e "$target" ]` 跟随链接、回答的是**目标**存在与否。技能目录若是指向未挂载磁盘或已移动位置的 symlink，`-e` 为假，于是"无所有权标记就保留"这道守卫被整个跳过，链接被直接替换、也不做备份。

这条**我本机复现不了**（Git Bash 造不出真 symlink，`ln -s` 直接失败），但代码路径是确定的：`install.sh:233` 的守卫、`:240` 的询问、`:269` 的备份三处都挂在 `[ -e ]` 上。新增 `exists()`（`-e` 或 `-L`），7 处判定全部改用它。CI 在 Linux 与 macOS 腿上新增真实断裂链接的装/卸/adopt 三段验证 —— 这条只能由 CI 证明。

**CI**

新增：非 Windows 平台拒绝驱动器路径且不得建出 `C:` 目录；Windows 拒绝 `C:relative` 与单前导分隔符；断裂 symlink 的默认保留（exit 3）、卸载不删、`--adopt` 才接管；技能正文里**不得再出现 `git stash`**；配方锚点改为 `rev-list --parents -n 1` 与 `git checkout -- `。

**验证**：CI 的 9 条 run-step 里 8 条在干净克隆上实跑（含 Windows）；`tests/mutations.py` 32/32。断裂 symlink 一段本机无法执行，由 CI 的两条 POSIX 腿覆盖。

## 0.13.0 — 2026-07-28

**退出码在两个平台上不一致**

`install.sh` 一直用 2 表示"拒绝"、1 表示"环境问题"、3 表示"装完但留下了不属于我们的东西"。`install.ps1` 全部走 `throw`，而 `throw` **一律退出 1**。实测同样三种拒绝：

| | install.sh | install.ps1（旧） |
|---|---|---|
| 相对路径 | 2 | **1** |
| 目标=源 | 2 | **1** |
| 未知选项 | 2 | **1** |

脚本化调用的人在两个系统上会拿到不同答案。改为共用一个 `Deny` 函数，退出码与 `install.sh` 逐条对齐；另外 PowerShell 的参数绑定会把未知开关当成自己的错误（也是 1），所以显式接管剩余参数。现在两边都是 2。

**目录名含空格的技能装得进去、卸不掉**

`for name in $(...)` 按默认 IFS 切分，一个叫 `two words` 的技能目录被拆成 `two` 和 `words`，两个都匹配不到任何东西，**真正那个目录永远留在那里**。实测：装 9 个，卸载报 0 removed，`two words` 残留。名字循环改为只按换行切分。本合集自己的 9 个名字都没有空格，所以这条一直没暴露 —— 但它是真的。

**marketplace 钉到标签**

`plugins[0].source` 之前只有一个裸 git URL，等于"永远拉 main 的最新"。官方文档确认 plugin source 支持 `ref`（分支或标签）与 `sha`（精确提交），本版加上 `"ref": "v0.13.0"`。选 `ref` 而不是 `sha`，是因为本仓库已有"标签一经推送即不可变"的规矩，钉标签同样可复现，而且不需要在写这个文件之前就知道提交的 SHA。CI 新增断言：这个 ref 必须等于 `v` + 当前版本号。

**CI**

双平台各补一份退出码契约（相对路径 / 目标=源 / 未知选项 → 2；`-h` → 0；卸载不存在的目标 → 0），以及空格目录名的装-卸往返。`tests/mutations.py` 增至 29 个 case。

**一次自己造成的丢失**

重建仓库时我用 `git filter-branch` 重写历史，它会重置工作区 —— 当时未提交的这两条修复被一并冲掉。随后我跑的 `git stash push` 实际无事可存，但它在没有改动时也返回 0，"已暂存"是个假信号。修复已按原脚本重做并重新验证。教训与本仓库反复出现的那类 bug 同形：**退出码 0 不等于做成了事**。

**仓库重建**

本版之前，有 4 个提交的作者邮箱不属于本账号。已重写为账号自己的 noreply 地址；由于强推只移动引用、孤立对象仍可按 SHA 取到，仓库整体删除后重建，15 个标签与 15 个 Release 全量恢复（正文逐字未改，总词数 3012 对 3012）。推送改用仓库级 deploy key，不再依赖账号级凭据。

**macOS 上又抛一个，而且是被“防止测空气”的守卫抦下的**：故障注入用的 `PATH="$Fi/bin:$PATH" command -v mv` 这种“前缀赋值 + 内建命令”写法，bash 5（Linux / Git Bash）下正常，**bash 3.2（macOS runner）下内建命令看不到那个临时 PATH**，于是找到的仍是 `/bin/mv`。守卫因此报了“this test would measure nothing” 并让 CI 变红 —— 这正是它存在的意义。改为先在 shell 里赋值再调用。本机是 bash 5，两种写法都正常，这条只能靠 CI 的 macOS 腿发现。

**验证**：CI 的 9 条 run-step 里 8 条在干净克隆上实跑通过（含 Windows）；`tests/mutations.py` 29/29。

## 0.12.1 — 2026-07-27

对署名标注做了一次机械对账 —— 把每个 `SKILL.md` 脚注声称的版本、NOTICE 行声称的版本，和该文件**实际最后被改动的 tag** 三者逐一比对。结果是系统性过期：

| | 最后改动 | 脚注声称 | NOTICE 行 |
|---|---|---|---|
| `spec-review` | v0.10.0 | **v0.7.0** | 当前 |
| `resolving-merge-conflicts` | v0.12.0 | **v0.11.0** | 当前 |
| `tdd` | v0.8.0 | **v0.3.0** | 当前 |
| `diagnosing-bugs` | v0.10.0 | 无 | **v0.4.0** |
| `implement` | v0.10.0 | 无 | **v0.8.0** |
| `worktree` | v0.10.0 | 无 | **v0.9.0** |
| `grill-me` | v0.9.0 | 无 | **v0.8.0** |
| `verification-before-completion` | v0.7.0 | 无 | **v0.6.0** |

9 个里 6 个脚注根本不带版本号，3 个带的都落后，最多落后 5 个版本（`spec-review` 的脚注停在 0.7.0，而 0.8.0–0.10.0 把整套基线解析重写了四遍）。

**根因是结构，不是疏忽**：同一份逐版本变更日志同时写在脚注和 NOTICE 两处，两处都会漂，而没有任何机制检查 —— 跟词数变成 CI 断言之前是同一回事。按 DOCTRINE 的**单一真相**改成：

- **NOTICE** 是唯一的逐版本记录。
- **脚注**只说这个文件相对上游是什么（保留了什么 / 删了什么 / 新增了什么）—— 这不会每个版本变 —— 并给出指向 NOTICE 的**绝对链接**（技能装到 `~/.claude/skills` 后相对链接会断）。
- **CI** 新增：每个脚注必须点名其上游、写明 MIT、指向 NOTICE；脚注里**不得出现版本号**（出现即意味着第二份变更日志又长回来了）；每个技能文件在 NOTICE 里**恰好一行**。

**其余清理**

- 0.10.0 加的三个“（续）/ 第 3 步”行把一个文件拆到两条里，已合并回各自的行。
- `spec-review` 行里的 `v2.1.218` 看上去像本仓库的版本，已改为“**Claude Code** v2.1.218”。
- 四个词数重算：442→465、428→449、877→892、1294→1326。
- 变异用例里硬编码的词数改为从文件里算 —— 它自己就因为词数变了而失效了一次。

**核实过的法律声明**：重新克隆上游 `mattpocock/skills @ ed37663` 逐字节比对 —— `tdd/SKILL.md` 的“正文未动”属实（唯一差异是脚注前的分隔线），`tests.md` / `mocking.md` “无改动”也属实。

**验证**：CI 的 9 条 run-step 里 8 条在干净克隆上实跑（含 Windows）；`tests/mutations.py` 现为 26 个 case，26/26 全红。

## 0.12.0 — 2026-07-27

第四份第三方审计，三条全部先复现再改。其中两条打在 **0.11.0 自己引入的代码**上。

**0.11.0 的换位修复引入了一条新的丢数据路径**

0.11.0 把"先删后移"改成"先挪开再换上"，并加了 `trap` 清理。但清理函数把 `outgoing` 当成垃圾 —— 而在换位窗口打开期间，它是那个技能**唯一的一份**。故障注入（PATH 上垫一个在特定 `mv` 上失败的假 `mv`）：

```
after injected failure: exit=1
  tdd/SKILL.md: GONE -- the installed skill was destroyed
  skills left:  8 of 9
  leftovers:    []          <- 备份被 trap 删了
```

也就是说 0.11.0 只是把"中断时丢"换成了"`mv` 失败时丢"。改为**先回滚、再打扫**：清理时若窗口未关且目标不存在，先把 `outgoing` 移回去；两次移动都失败则**保留** `outgoing` 并打印它的路径 —— 留个杂目录难看，但丢数据更糟。同一形状在 `install.ps1` 用 `$script:swapTarget` + `try/catch` 实现。

修复后同一注入：`tdd/SKILL.md: present`、`9 of 9`、脚本打印 `restored tdd (install did not finish)`。PowerShell 侧用函数遮蔽 cmdlet 的办法注入，旧代码 `tdd=GONE / 8 of 9`，新代码 `tdd=present / 9 of 9 / restored`。

**0.11.0 新写的 `git stash push` 缺 `-u`**

第 8 步让 rebase 先把用户的文件 `git stash push -- <paths>` 停靠。但第 4 步刚刚把它们移出索引 —— 一个原本作为**新文件**暂存的路径现在是 untracked，而 `git stash push` 会因为不认识这个 pathspec 而**整条失败**：

```
$ git stash push -- brandnew.txt
error: pathspec ':(prefix:0)brandnew.txt' did not match any file(s) known to git
EXIT=1
```

**这正是第 4 步自己讲透了的陷阱**，换了个命令重犯一次。停靠没发生，`--continue` 照样拒绝，读者又回到那个 `git add`。改为 `-u`，并要求读退出码、失败就停。另外补一句 `pop` 之后的状态说明：文件回来是**未暂存**、新文件回来是**未跟踪**，那是第 4 步留下的状态而不是恢复失败 —— 少了这句，一个只看到"没回到暂存区"的模型很可能判定恢复失败然后 `git add`，又绕回原坑。

**前导空白让相对路径蒙混过关**

守卫的两个检查顺序反了：`case` 的第一条分支放行 `""`、`" "*`、`"\t"*`，随后的空白检查只判"是不是全空白"。于是 `" /tmp/x"` 两关都过。POSIX 下它的第一个路径分量就是一个空格，是**相对路径** —— 实测 `CLAUDE_SKILLS_DIR=" /tmp/leadspace"` **exit 0**，9 个技能被装进仓库根目录下一个名为 `" "` 的目录。改为**先判空白、再判绝对**，并删掉那条前导空白豁免。判空白改用 shell 模式 `*[![:blank:]]*` 而不是 `tr -d ' \t'`（BSD 与 GNU 的 `tr` 对参数里的反斜杠-t 是否表示制表符并不一致）。含空格的**真**绝对路径不受影响。

**变异测试入库**

0.10.0 与 0.11.0 的记录里写着"12 项 / 18 项变异测试全部会红"，但整个仓库里搜不到 `mutation` —— 这个数字**任何人都无法复现，包括三个月后的我自己**。现在是 `tests/mutations.py`：23 个 case，直接从 `.github/workflows/ci.yml` 里抽 step 来跑（因此不会和 CI 漂移），存活即非零退出。

```
$ python tests/mutations.py
caught    installer: cleanup deletes the backup
caught    skill: stash push loses its -u
...
23/23 caught
```

写完第一版后跑下来，23 个里有 **2 个自己就是空转的**：一个往 `case` 里已经匹配的分支**后面**加了一条（`case` 取第一个匹配，加在后面是死代码），另一个把 ```` ```bash ```` 改标成 ```` ```sh ````（抽取器早已改成接受任意围栏，改标签藏不住任何东西）。两个都先单独验过“变异后行为真的变了吗”才确认是用例错而非断言漏，换成真能重现缺陷的写法后 23/23 全红。—— 变异测试本身也会写出哑弹。

发布清单第 7 条相应改写：新增断言要同步加一个 case；涉及"失败时会怎样"的断言必须用**故障注入**，并且**先确认它在旧代码上是红的**。这一条是本轮吃的亏 —— 我第一次的故障注入把 `C:/...` 放进了 `PATH`，Git Bash 按冒号把它拆坏，shim 从未被找到，测试全绿而 bug 还在。

**CI**

三条新断言，双平台各一份：故障注入下技能必须存活且不留备份目录（bash 用 PATH shim，PowerShell 用函数遮蔽 `Move-Item`）；前导空白/纯空白的 `CLAUDE_SKILLS_DIR` 一律 exit 2 且不得在仓库里建出空白名目录，而含空格的真绝对路径仍要装满 9 个；代码块里的 `git stash push` 不带 `-u` 直接红。

**验证**：CI 的 9 条 run-step 里 8 条在干净克隆上逐条实跑通过（含 Windows），第 9 条 `plugin validate` 需要 npm 只在 CI 跑；`tests/mutations.py` 23/23。故障注入在两个平台都确认了旧代码红、新代码绿。

## 0.11.0 — 2026-07-27

三份独立第三方审计并行（技能逐命令复现 / CI 变异测试 / 声明对账），每条发现先自己复现再改。**68 个变异里 36 个曾经存活**，这一版把它们关掉。

**技能：塌陷的第三种形状**

前两种都是"命令不报错，只是安静地做了更小或更错的事"。这一种相反 —— **命令响亮地失败，但报错指错了原因，而最顺手的修复恰恰造成伤害**：

- rebase 冲突解决后，`git rebase --continue` 报 *"You must edit all merge conflicts and then mark them as resolved using git add"*，而 `git diff --name-only --diff-filter=U` 是空的。真正的原因是第 4 步刚从索引里救出来的用户文件现在处于未暂存状态。视野里唯一的未暂存路径就是它，于是 `git add user.txt` —— **rebase 把整个技能要保护的东西提交了进去**。实测 merge / cherry-pick / revert 三个都 exit 0 且用户工作完好，只有 rebase 中招。改为 rebase 分支先 `git stash push -- <那些路径>`，`--continue` 之后 `git stash pop`。

**其余技能修正（全部先复现）**

- **操作表的分支不互斥。** `git rebase -r` 重建 merge 冲突时，`MERGE_HEAD` 与 `rebase-merge/` **同时存在**。按表格阅读顺序命中第一行，边界取到的是 rebase 刚建的那个提交（实测 `0a20cd2` vs 真值 `7331b17`），收尾命令 `git merge --continue` **exit 0、建了提交、rebase 原地不动**。表格现在明写自上而下读、命中第一行即停，rebase 行排在 merge 行之前。
- **`git merge-base` 也会塌成第一个。** 交叉合并（团队反复把 main 合进特性分支就会产生）有多个 merge base，`merge-base` 打印其中一个、exit 0。实测两个 base 算出的"操作带来的文件"清单完全不同（`a.txt` vs `b.txt`）—— 选错既把操作的文件留在索引里，又把用户的文件踢出去。改用 `merge-base --all` 并对全部 base 取并集。
- **第 9 步的取证命令在两个路径以上时匹配不到任何东西。** 模板把所有路径塞进**一个**带引号的 pathspec，成了一个含空格的单一 pathspec：空输出、exit 0，而同一段自己写着"空结果读起来就像全被提交了"。重命名场景强制触发（第 3 步要求新旧两个路径都列上）。改为每个路径一个 `:(top)` 参数。
- **`git log --name-only` 对 merge 提交一个文件都不打印。** 被卷进 merge 提交的用户文件在一份看起来完整的清单里完全隐形。`git rebase -r` 也产生 merge 提交，所以这条对 rebase 同样适用。加 `--diff-merges=first-parent`。
- **`core.quotePath=false` 管不了含空格的路径。** `--porcelain` 对任何含空格/引号/反斜杠的路径无条件加 C 引号，`core.quotePath` 只管非 ASCII。粘回去两个方向都错：`restore --staged` 整条被拒（该救的文件留在索引里），第 9 步静默匹配为空（读成"被提交了"）。改用 `--porcelain -z`。
- 第 3 步"仅工作区改动的文件不在索引里"是**错的** —— 它们是 tracked 的，索引里有 HEAD 版本。结论方向没错，但它教给读者一个错误的索引模型，而分类正建立在这个模型上。

**安装器：两个平台对同一份文件给出相反答案**

`install.sh` 用 `head -n 1 | grep -qF`（**子串**、大小写敏感），`install.ps1` 用 `-eq`（**全等**、大小写**不**敏感）。实测同一个 `.lean-skills`：

| 首行 | install.sh | install.ps1 |
|---|---|---|
| 精确 | 认领 | 认领 |
| 全大写 | 保留 | **认领** |
| 前面加 `# ` | **认领** | 保留 |
| 后面加一句 | **认领** | 保留 |

后果：用户自己写的 `.lean-skills` 只要引用了这句话，`install.sh --uninstall` 就 `rm -rf` 掉整个目录。两边统一为**首行全等、大小写敏感**（容忍尾部 CR），双平台实测四种输入结果一致。

**安装器：中断会留下会被当成技能加载的目录**

原来是 `rm -rf` 目标然后 `mv`，两步之间技能**根本不存在**；全脚本 `trap` 数量为 0，孤儿 staging 目录再跑一次 install 和一次完整 uninstall 都清不掉，而 Claude Code 会把它当成一个名叫 `.lean-skills-staging-1352` 的技能加载。改为先把旧目录改名挪开、换上新的、再删旧的（窗口里是一次 rename 而不是空缺），并加 `trap cleanup EXIT INT TERM HUP` / PowerShell 的 `try…finally`。

**CI：两条哑弹**

- `test -s A && test -s B` 在 `set -e` 下**左侧是豁免的**（实测继续执行）—— "代码块抽取结果为空"这件事永远不会让 CI 变红。拆成两条。
- "退役错误不许回来"的循环里第二个条件 `! grep -qF 'Never fall back to @{upstream}'` **恒假**，因为上一行刚断言过那句话必须存在。于是把 0.9.0 修掉的 `@{upstream}` bug 原样写回代码块，四个 step 全绿。改为只在代码块内查禁用命令。

**CI：`platform parity` 守卫的四个绕过口**

它只读 `jobs.install` 每个 step 的 `if:` 字符串，于是：给任意 step 加 `continue-on-error: true`（永远不会让 job 红）、把 `macos-latest` 从 matrix 删掉或 `exclude` 掉（守卫照样打印"这些也在 macOS 上跑"，而 macOS 一个 step 都没跑）、新增一个 job 装满 Linux-only step、或者 `if:` 不动而在 body 第一行 `[ "$(uname)" = Darwin ] && exit 0`。四种全部堵上，含"matrix 必须是三个平台且无 exclude"这条它自己的前提。

**CI：其余覆盖空洞**

退役名在 **uninstall** 路径的清理（两个平台都没测，正好放跑了"`code-review` 顶掉内置命令"这个注释里点名要防的场景）；`--uninstall --adopt` 的成功路径（只有 Windows 有）；"覆盖已属于我们的目录前要询问"（此前的用例用的是无标记目录，会在更早的分支 continue 掉，根本走不到 prompt）；标记语义的三种变体；`install.ps1` 的 CRLF（`.gitattributes` 要求，但只有 `install.sh` 有检查）；`tdd/tests.md`、`mocking.md` 必须存在；`plugin.json` 与 `marketplace.json` 的 name 一致、source URL 指向本仓库；blurb 左边界（`19 skills, 5 resident` 含子串 `9 skills, 5 resident`，此前能过）；CHANGELOG 版本号必须是 `## ` 标题（改成 `## Unreleased (would have been …)` 会连带关掉 NOTICE 覆盖检查）；path-printing 配方由"至少 6 条"改为**精确 10 条**（`-ge 6` 下这个技能的四条核心配方可以全删而 CI 全绿）；代码块抽取不再只认 ```` ```bash ````（改标 ```` ```sh ```` 就能把一条配方从所有检查里摘出去）。

**另外两条我自己写的同型 bug**

- `grep -q $'\r'` 在 Git Bash 下**永远不匹配**（MSYS 把 CR 当行尾剥掉）—— 也就是说 `install.sh` 的 CRLF 检查在本机是空转、只在 CI 里活着，同一条断言在写它的地方和跑它的地方行为不同。改走 `od -c` + `grep -qF '\r'`（无管道，避免 SIGPIPE）。
- CHANGELOG 版本覆盖循环用 `v.split('.')[1] >= '8'` 做字符串比较，`'10' >= '8'` 为假 —— 从 0.10.0 起这条检查会静默失效。改为整数元组比较。

**文档：对自己流程的自述**

三条破绽全在这里，归属与技术事实两块审计逐条实测通过：

- 「八条 CI 腿逐条实跑通过」—— CI 有 **9** 条 run-step，这个数字是 0.9.1 留下的。改为"9 条里 8 条本地跑过，`plugin validate` 需要 npm 只在 CI 跑"。
- 「发布清单从 0.9.1 的变更记录里**搬**到 README」—— 两处都错：完整清单从来不在任何版本条目里（它是本文件末尾的附录），而且没被搬走，旧的那份仍在、仍写着 `wc -w`。本版真的处理掉，README 是唯一一份。
- 「0.9.0 声称补了逐文件条目，实际**一条都没补**」—— 假的，它补了 0.8.1 和 0.9.0 两条，缺的是 0.8.0 和 0.8.2（正是同一条目下面自己列出的缺口）。**同一条 CHANGELOG 里两句自相矛盾，而且是在指责别人虚报时自己虚报。**
- README 把 `resolving-merge-conflicts` 标成"微调"，实际上游 134 词 → 本仓库 2337 词，9 步里 5 步是新写的；`diagnosing-bugs` 同样标错。改为"骨架 + 重写"与"扩写"。
- README 说"CI 会重算每一个箭头"，实际只重算 4 个右侧值；`plugin validate` 写的命令与 CI 实跑的两条不是同一条；NOTICE 的 `CLAUDE.md`/`AGENTS.md` 一格自 0.7.0 起为假；`skills/tdd/{tests,mocking}.md` 工作区是 CRLF 而 `.gitattributes` 要求 LF。全部改正。

**验证**：CI 的 9 条 run-step 里 8 条在干净克隆上逐条实跑通过（含 Windows）；第 9 条 `plugin validate` 需要 npm，只在 CI 跑。本轮新增与修复的断言做了 **18 项变异测试，18 项全部确认会红**。标记语义的四种输入在两个平台各跑一遍，结果一致。

## 0.10.0 — 2026-07-27

自审 + 两份第三方审计（针对 v0.9.2）。这一轮的主题是：**把"塌陷"写进技能本体，把"记得做"写成 CI 断言。**

**技能：塌陷的第二种形状**

五轮以来每个 bug 都是"命令不报错，只是安静地做了更小或更错的事"。这次把它拆成两种形状写进 `resolving-merge-conflicts` 的开头：**塌成空**（`$(...)` 空值仍然 exit 0）与**塌成第一个**（便利的访问器安静地只返回第一个元素）。后者本版内实测到三个实例：

- **`git rev-parse MERGE_HEAD` 在 octopus merge 下只给第一个头**（实测：`MERGE_HEAD` 文件两行，`rev-parse` 返回一个，exit 0）—— 第二个父带来的改动会被当成用户的而踢出索引。改为按文件逐行读、逐个算 merge-base 并取**并集**。
- **`<commit>^` 永远是 parent 1**，而 `cherry-pick -m 2` 的主线是 2（实测：`-m 2` 跑完后 `.git` 里找不回那个 `n`）。diff 改为显式 `^<n>`，并说明用 `rev-parse -q --verify <REF>^2` 先判断目标是不是 merge commit、是就问用户。
- **`refs/remotes/origin/HEAD` 只在 clone 时写一次，`git fetch` 从不刷新**（实测：远端默认分支改名后，`symbolic-ref` 仍返回旧名且 exit 0）。`spec-review` 改为 **`ls-remote --symref` 在前**，`symbolic-ref` 降为离线兜底并要求在报告里声明可能陈旧。

其余技能修正：操作识别表补 `git am`（`rebase-apply/` **带** `applying`，否则会被当成 rebase）与"四者皆无"一支（`git stash pop` / `git apply --3way` 冲突时不留任何标记，而后续步骤假设存在"入侧"）；第 9 步的 pathspec 加 `:(top)`（在子目录里跑会静默匹配不到任何东西，读起来就像"全被提交了"），并对 merge 改用 `%P` 列出全部父提交；无共同祖先时的空树补救命令从散文提升为可运行代码块；所有会打印路径的命令补齐 `core.quotePath=false`（此前漏了三条）；`diagnosing-bugs` 更正 `grep` 退出码语义（无匹配是 1，2 是出错）；`spec-review` / `implement` 的 `.plans` 路径补子模块与非仓库两种回退。

**CI：把哑弹换成实弹**

- **锚点改为绑定代码块。** 审计的反向变异测试显示 10 个里逃了 9 个 —— 把一条命令改成错的、但把原字符串留在散文里，`grep -qF` 依旧全绿。现在先用 `awk` 抽出 fenced bash 块，只在块内找锚点。
- **一条彻底的哑弹。** `-notmatch 'THEIRS'` 在 PowerShell 里不区分大小写，而 `implement/SKILL.md` 正好写着 "theirs to act on"，这条断言从未可能触发。`OLD`/`MINE` 同病（分别命中 4 个和 1 个技能文件）。全部换成不可能碰撞的哨兵串，并新增一条自检：哨兵串一旦出现在技能正文里，CI 直接红。
- **Windows 腿补齐契约**：两次干净安装的退出码、无 `-Yes` 无控制台时的同意分支（含 `-Adopt`，此前**完全没测**）、不带 `-Adopt` 的干净卸载要求 SKILL.md 与 `.lean-skills` 都归零、原子换名的文本断言。
- **`platform parity` 守卫的三个绕过口**：条件子串匹配（`!= 'Windows' && arch == 'X64'` 能蒙混过关）、无名步骤直接 `continue`、重名步骤可冒充豁免项。三个均已变异测试确认会红，并新增"豁免名必须对应真实存在的步骤"。
- **安装器名单改为精确相等**而非包含关系：旧的 ghost 启发式只看带连字符的名字，编造一个 `planner`、或把 `tdd` 删掉、或把一个常驻技能列到手动行，三种都逃得掉。现在两个桶各自集合相等。
- 新增：桶归属断言（RESIDENT/MANUAL 具体集合，而不只是 5/4 个数）、所有权标记首行的字面契约（改了它，所有已有安装都不再可认领）、`description` 必须有非空值且常驻技能不得过短、CHANGELOG 版本号按边界匹配（子串匹配下 `0.9.2` 能被 `0.9.20` 满足）、安装后的目录要与源逐文件 `diff -r`（之前只数数量）。

**NOTICE：声明与事实对账**

0.9.0 的 CHANGELOG 声称"补上 0.8.0–0.9.0 的逐文件条目"与"四行词数统一口径"。前者只补了 0.8.1 与 0.9.0 两条，缺 0.8.0 与 0.8.2；后者没做（四个箭头左侧是 `LC_ALL=C wc -w`、右侧是空白分隔计数，每个箭头两端各一种口径）。本版补齐：

- 词数口径改为 **locale 无关的空白分隔计数**（`awk '{n+=NF}'`）并写明理由 —— `wc -w` 对同一份 `worktree/SKILL.md` 在 `LC_ALL=C` 下是 851、UTF-8 locale 下是 877，BSD 与 GNU 又各不相同，写进文档根本无法复核。八个数字全部重算：上游 580/913/1069/1104（取自文件顶部钉住的那两个提交），本仓库 442/428/877/1294，历史峰值从 1581 改正为 **1642**（已从 `v0.6.0` 标签直接重算验证）。
- 补齐 0.8.0 的七行逐文件条目，以及 0.8.2 / 0.9.2 / 0.10.0；0.9.1 未改动任何衍生文件，也明写出来，不留缺口。
- CI 新增：每一个箭头都要被重算比对（多出一个无人校验的箭头就红），且 CHANGELOG 里发过的每个 0.8+ 版本必须在 NOTICE 里有交代 —— 这条断言当场就报出了 0.8.0/0.8.2/0.9.1 三个缺口。

**发布流程**：README 的「维护」一节新增发布清单，并加一条：新增的断言必须做变异测试。（本文件末尾那份旧附录当时**没有**被移走，仍写着 `wc -w`——0.11.0 才真的处理掉。）

**验证**：CI 的 9 条 run-step 里 8 条在干净克隆上逐条实跑通过（含 Windows）；第 9 条 `plugin validate` 需要 `npm install -g`，只在 CI 里跑。本轮新增的断言做了 12 项变异测试，全部确认会红。

## 0.9.2 — 2026-07-27

第六方审计（针对 v0.9.0）。三条 Important 全部先复现再修。

- **完成范围的边界是错的。** Step 8 让用 `git rev-parse ORIG_HEAD` 作起点，实测：单次 cherry-pick **根本不设 `ORIG_HEAD`**（exit 128）；rebase 虽设，但 `ORIG_HEAD..HEAD` 会把**新 base 上原本就有的提交**一起算进来（夹具里 `onbase.txt` 混入，会误报用户改动被卷走）；merge 和 revert 则从未记录过任何 SHA，判据却要求"Step 8 的 SHA"。改为在第 1 步的表格里按操作各自记录边界（merge/单次 cherry-pick/revert 用当前 `HEAD`，rebase 用 `rebase-merge/onto`，多提交序列用 `.git/sequencer/head`），并新增第 9 步：先对用户路径直接问 `git status --porcelain -- <paths>`（精确且与操作无关），再用边界交叉核对，merge 用 `git diff --name-only HEAD^1 HEAD`。
- **`ls-remote` 只问不取。** `spec-review` 解析出默认分支后直接 `merge-base`，而在 `--single-branch` / 浅克隆（CI 的常态）里那个对象根本不在本地。实测（`file://` 真实传输）：`ls-remote` 正确返回 `main @ d4ca7a5`，但 `cat-file -e` 与 `merge-base` 双双 exit 128 —— 评审就此停住。补上 `git fetch origin "+refs/heads/<default>:refs/remotes/origin/<default>"`，并说明 fetch 后仍失败意味着浅克隆边界，要停下或经授权 deepen。
- **`gh` 失败不等于没有 PR。** 未安装、未认证、离线、限流、API 报错都不是"没有 PR"的证据，而原文会滑到默认分支继续审。改为：只有明确的 "no pull requests found" 才允许回退，其余原样报错并停止。同时 `baseRefOid` 拿到后要先 `git cat-file -e` 确认对象在本地，不在就 fetch。

**CI 的 SIGPIPE 修复**（macOS 首次跑新夹具就红了，正是双平台覆盖的价值）：`set -o pipefail` 下 `git ... | grep -q` 会因 `grep` 命中即退出而让左侧收到 SIGPIPE，整条管道返回 141。Linux 上碰巧不触发，macOS 时序不同就炸。全部 24 处改为 here-string（`grep -q pat <<<"$(cmd)"`），无管道即无 SIGPIPE。

**CI** 新增按审计要求的五种完成范围夹具（单次 cherry-pick、rebase 到已有提交的 base、merge 的 first-parent、revert、边界与 `ORIG_HEAD` 的对照）以及 `ls-remote` 不下载对象的夹具，全部在 Linux 与 macOS 两个平台跑。

### 关于被移动过的 v0.9.0 标签

审计指出：`v0.9.0` 的 Release 发布于 `6874a51`，而我随后为修 macOS CI 覆盖用 `git tag -f` 把标签移到了 `f4c2810`。同一版本号在不同时间指向不同内容，破坏可复现构建与供应链追踪。**这是我的错误做法。**

处理：标签**不再移动**（再动一次只会更糟），修复以 0.9.1 / 0.9.2 发布。发布清单加一条：**标签一经推送即不可变** —— 发版前先确认标签不存在，修复一律走新版本号。需要可复现安装的场景请钉 commit SHA 而不是 `v0.9.0`。

## 0.9.1 — 2026-07-27

macOS 覆盖补齐 —— 上一版 macOS 只执行了 CI 五个步骤里的一个。

- 两个 git 配方回归（正是因为合并技能连出三轮 bug 才加的）此前被 `if: runner.os == 'Linux'` 挡掉，从未在 BSD 的 `comm`/`find`/`sed`/`grep` 与 bash 3.2 下跑过。改为 `!= 'Windows'`，macOS 实测通过。`paste -sd,` 换成 `tr`/`sed`，不再赌 BSD 的参数解析。
- 新增 **worktree 与 .plans 路径配方**的回归 —— 这两条契约此前**任何平台都没测过**，而后者正是 0.6.0 整个计划枢纽的地基。覆盖：`check-ignore` 对尚不存在目录的假阴性、`WTDIR` 三处一致、计划路径从 linked worktree 内解析到主检出、worktree 拆除、非仓库目录的 Step 0 判定。
- 新增 **`platform parity` 守卫**：任何步骤只要被限制在单一平台，CI 直接红，除非在豁免表里写明理由（目前三条：`install.ps1` 只有 Windows 有 PowerShell、`manifests` 是纯文件解析、`plugin validate` 装 npm 包跑一次够）。已做变异测试确认它真会红。
- 发布清单加一条：**任何改动都要双平台落地并各自有断言**。一端有断言、另一端没有，等于没有 —— 这一版和上一版各栽过一次。

**技能本身的 macOS 适配**（静态扫描 + macOS 实跑确认）：技能正文只用到 `git`/`gh`/`grep`/`find`/`echo`/`test` 与包管理器，零处 GNU 专有惯用法（`sed -i`、`readlink -f`、`grep -P`、`stat -c`、`date -d` 等均无），零处 Linux 专有路径；用到的 git 子命令最低要求 2.23（`restore --staged`），macOS 自带 Xcode CLT git 为 2.39+。

## 0.9.0 — 2026-07-27

三份独立审计并行：命令级实测、CI 变异测试、声明对账。这轮的目标是把**故障形状**修掉，而不是再修一批实例。

五轮下来每个 bug 都是同一件事：**命令没报错，只是安静地做了更小或更错的事**。这次按四条通用轴扫，而不是按已知实例：命令替换塌陷、退出码 0 不等于对、git 打印出来的名字不等于能喂回去的 pathspec、外部工具的字段得先跑过再写。

**Critical（全部先复现）**

- **`$(git merge-base HEAD MERGE_HEAD)` 在无共同祖先时塌陷成空**，`git diff --name-only MERGE_HEAD` 变成"对工作区比较"，exit 0。实测：分类结果**完全反过来** —— 合并合法带来的文件被判成用户的并被踢出索引，用户的 `user-notes.txt` 留在索引里进了合并提交。讽刺的是 `spec-review` 正好用整整一段教这个坑。现在两步走、读打印值、判空，并给出无共同祖先时的正确做法（对空树 diff）。
- **`gh pr view --json baseRepository` 里没有这个字段**（合法的只有 `baseRefName`/`baseRefOid`）—— 0.8.2 我"修复" PR 基线时引入了一个不存在的字段，整条 PR 路径必然 exit 1，模型最自然的解读是"这里没有 PR"，于是滑到下一档用默认分支审。改用 **`baseRefOid`**：它本身就是 base 提交，整套"分支名转 ref"的推理都不需要。
- **本地存在过期同名分支时 `merge-base dev HEAD` 会成功**，给出一个陈旧基线——比"不存在时响亮失败"危险得多，而 0.8.2 的措辞恰好只描述了失败那一半。
- **默认分支兜底 `origin/main` 会静默选错**：默认分支是 `dev`/`trunk` 而 `main` 恰好也存在的仓库（gitflow、改名迁移期）会正常解析到错基线。改为先问远端（`git ls-remote --symref origin HEAD`），实在猜的要在报告里说是猜的。
- **重命名只被救回一半**：`--name-only` 对重命名只给新路径，旧路径的删除仍在索引里、随合并提交落地。改用 `--name-status -M`。
- **`worktree` 的守卫检查的是一条不会被创建的路径**：`:41` 允许选 `worktrees/`，代码块却写死 `.worktrees/`，于是忽略写在 A、检查 A、创建 B，守卫 exit 0 放行。目录名收进 `WTDIR` 一个变量，三处共用。

**Important**

- 非 ASCII 路径被 `core.quotePath` 八进制转义，粘回去的报错与"未跟踪路径"的报错**字面相同** —— 模型会照着 0.8.1 的教学把一个已跟踪文件从救援名单里删掉。全程加 `-c core.quotePath=false`。
- 完成判据用 `git show --stat HEAD` 取证，而技能自己要求多提交 rebase 循环 —— 前几个提交它看不见。改用 `git log --name-only <起点>..HEAD`。
- `worktree` Step 0 把非 git 目录和裸仓库都判成"普通检出"（两个变量都空、恰好相等）。增加 `--is-inside-work-tree` 前置。
- `.plans` 路径表达式三处都没加引号（含空格的 worktree 路径下 `mkdir -p` 会 exit 0 建出垃圾目录），且在子模块里解析进 `.git/modules/`。三处加引号并注明子模块例外。
- 空仓库里 `git rev-parse HEAD` 把字面 `HEAD` 打到 stdout —— 一个看起来完全合理的"SHA"。`implement` 第 3 步注明必须是 40 位十六进制。
- `[DEBUG-a4f2]` 在 `grep` 里是字符类，清理命令会误匹配半个代码库。改为 `grep -rF '[DEBUG-'`。

**CI：从测已知故障改为测契约**

变异测试显示 41 个变异里有 21 个 CI 抓不到。补上：Windows 腿补齐 `-Adopt` / 退役名 / legacy 升级三项契约（此前**完全没有**，而这正是 0.8.0 那次 breaking fix 的全部内容）；锚点带 payload 且加反向断言（此前 `grep 'Never fall back to'` 只匹配前缀，把整句改成推荐 `@{upstream}` 仍然全绿）；新增外来 marker 内容、技能名上的非目录、无 tty 时不得覆盖、相对路径、干净卸载 exit 0、原子换名、总技能数与版本链一致性、安装器名单不得虚构技能名；守卫的残留检查从写死的 `skills/a` 改为整个 `skills/` 目录清单比对；夹具新增无共同祖先与重命名两例。

发布清单加了两步：**更新 NOTICE 的逐文件行并用 `wc -w` 重算词数**、**本地把 CI 的每条腿在干净克隆上原样跑一遍**（这一步这次抓到了两个我自己写的 CI bug：`$srcDirs` 是计数不是列表、锚点没跟着技能改）。

**文档**

- NOTICE 仍写着内置 `/code-review`「覆盖正确性/安全/清理」，而 0.8.0 的 CHANGELOG 声称已同步修 NOTICE —— 声明与事实相反，现已改正（安全属 `/security-review`）。
- NOTICE 的词数箭头两侧用了两种计数法（上游 `wc -w`、本仓库 `awk NF`），四行全部统一为 `wc -w` 并注明口径；`spec-review` 一行已过期两版。
- NOTICE 补上 0.8.0–0.9.0 的逐文件条目（此前停在 0.7.0）。
- DOCTRINE 的「零上下文成本」按 0.7.0 已在 README 采用的措辞改为「不花常驻 description 成本，正文在调用时进入上下文并留在会话里」。

## 0.8.2 — 2026-07-27

第五方审计。两条发现均先复现再修。

- **Important —— PR 的 `baseRefName` 是分支名，不是可用的 ref。** `gh pr view --json baseRefName` 返回 `dev` 这样的裸名，而本地通常只有 `origin/dev`。实测：`git rev-parse --verify dev` 退出 128，`git merge-base dev HEAD` 同样失败 —— 随后按原文会滑到下一档，**用默认分支 `main` 去审一个目标为 `dev` 的 PR**，diff 边界完全错位，所有发现都是虚构。现在要求：用 `baseRepository` 匹配对应的 remote（fork PR 的目标是上游 remote，不是 `origin`），解析成字面的 `refs/remotes/<remote>/<baseRefName>`，缺了就 fetch；**PR 存在但基线解析不了时停下报告，不许退回默认分支**。
- **Minor —— `--adopt` 在用户确认之前就宣称正在覆盖。** 提示打印在确认闸门之前，用户答 No 之后又打印 `kept`，前后矛盾（实测：说了「正在覆盖」，用户内容原样保留）。提示移到确认之后、真正复制之前。

CI 的 git 配方回归新增一例：推一个 `dev` 分支到远端后，断言裸 `dev` 解析不了而 `refs/remotes/origin/dev` 可以 —— 这正是上面那条 Important 的成因。

## 0.8.1 — 2026-07-27

第四方审计。三条 Important 全部先复现再修，且全部出在 0.8.0 我自己重写的技能里。

- **`git restore --staged` 会被 untracked 路径整条打掉。** 第 2 步把 staged、仅工作区、untracked 三类都归为「用户的」，第 3 步却让它们一起 restore。实测：`git restore --staged -- s.txt u.txt` 因 `u.txt` 不在索引里而报 `pathspec did not match`，**整条命令失败，真正 staged 的 `s.txt` 原样留在索引里**，随后照样进合并提交 —— 正是这一步要防的事。现在三类分开列出，只对 staged 那一类执行 restore，并要求 restore 后复查索引。
- **cherry-pick / revert 冲突下命令写死了 `REBASE_HEAD`。** 代码块里只有 `REBASE_HEAD^ REBASE_HEAD` 一行，注释却说它同时适用于三种操作。实测 cherry-pick 冲突中该命令 `fatal: ambiguous argument`。四种操作各写一行，并注明只跑第 1 步表格里匹配上的那一条。
- **`spec-review` 拿 `@{upstream}` 当兜底基线，会漏掉整个已推送的分支。** feature branch 跟踪的是 `origin/feature`，一旦推送，`merge-base HEAD @{upstream}` 就等于 HEAD，diff 是空的 —— 只审到未提交的碎片，分支上每个提交静默逃过。实测确认。兜底改为：PR 的 base 分支 → `origin/HEAD` 的默认分支 → 报告「无基线」并停止；并明确写出**永远不要退回 `@{upstream}`** 及其原因。

**CI 新增 git 配方回归**（这个技能连续三轮出问题，靠读代码守不住）：真实 fixture 跑 merge / cherry-pick / 已推送分支三种场景，断言合并范围取自 merge base、`HEAD..MERGE_HEAD` 确实会多算、只 restore staged 那一类能成功而带 untracked 会失败、用户的暂存文件不进合并提交、仅工作区与 untracked 改动仍在、cherry-pick 下 `REBASE_HEAD` 确实解析不了、`@{upstream}` 在已推送分支上确实塌成空。命令锚点绑回 SKILL.md 原文。

**其余**

- 安装器的重启提示改为按情况区分：首次创建目标目录才提示重启，之后按官方的热生效行为提示无需重启。
- README 的升级段落此前既说「以退出码 3 告知」又说「静默地什么都不做」，自相矛盾；改为如实描述（会装上全新技能、已有的 8 个不动、退出码会说但输出不红）。
- `--adopt` 现在逐个列出将被接管替换的目录，而不是默默覆盖。
- CI 步骤名 `code-review's diff recipe` 更正为 `spec-review's`。

## 0.8.0 — 2026-07-27

三名独立审计员并行审查 `a4e3d10`。四个 Critical 全部先复现再修。

**Critical — 升级路径彻底断裂（两名审计员独立发现）。** 0.7.0 引入的所有权标记只在新装时写入，而 0.6.0 及更早版本装的目录**没有标记**。于是对每一位现存用户：`--uninstall` 删 0 个并声称它们"不是我们装的"，随后 `install` 拒绝覆盖 8/9，**退出码 0**，用户静默停留在旧版；改名前的 `code-review/` 原封不动，继续遮蔽内置 `/code-review` —— 0.7.0 的头号卖点对所有老用户完全落空，而 README 给的唯一处方（先卸再装）实测一个文件都不动。

修法：新增 `--adopt` / `-Adopt`，把无标记的同名目录认领为本合集的；默认不认领但**以退出码 3 明确告知**，不再假装成功。同时引入"已退役技能名"清单（目前是 `code-review`）—— 它已不在 `skills/` 里，此前任何循环都碰不到它，`--adopt` 现在会一并清除。

**Critical — Windows 守卫被 junction 指向仓库根整个绕过。** 前缀比较用 `GetFullPath`（不解析 reparse point），canary 只从目标**向上**走 —— 而源在目标之内时 canary 在下方，永远看不见。实测：`CLAUDE_SKILLS_DIR` 设为指向仓库的 junction，**9 个技能目录连同 9 个标记直接写进仓库根**，安装与卸载都不被拒。修法：双向 canary —— 再往目标写一个、从源向上走一遍。8 个向量（含 junction 指向仓库根）复验全部拒绝、仓库零残留。

**Critical — 合并冲突的"操作触及文件"算错。** `git diff HEAD MERGE_HEAD` 包含**本侧**自 merge-base 以来改过的文件，于是用户编辑过、而本次合并根本不碰的文件被误判成"操作自己的改动"，照旧被提交进去。实测：用户改的 `g.txt` 被漏判。改为从 merge-base 起算（`git merge-base HEAD MERGE_HEAD`），rebase/cherry-pick/revert 用 `<REF>^..<REF>`；补上 revert 的 `REVERT_HEAD`。

**Critical — 即使正确识别了用户的文件，照第 6 步做仍会把它们提交。** 技能自己写着"合并提交会带走整个索引"，却没给出纠正动作。新增第 3 步：解决冲突**之前**先 `git restore --staged` 把用户的文件移出索引。实测：修正后合并提交只含冲突文件，用户的 `g.txt`/`u.txt` 仍是未提交状态，完成判据这才成立。

**其余**

- `spec-review`：删掉"内置 `/code-review` 覆盖安全"的说法 —— 官方文档写的是"correctness bugs and reuse, simplification, and efficiency cleanups"，**没有安全**；安全是 `/security-review`。这条错误说法此前还指挥 fork 子代理主动跳过安全审查，等于推荐流水线里安全无人覆盖。同步修 README/NOTICE/implement。
- `spec-review`：补 `argument-hint` 与 `$ARGUMENTS`（fork 子代理拿不到调用方上下文，参数怎么到手此前全靠未声明的约定）；无 upstream 时的兜底改为 `origin/HEAD` 并在失败时把"缺 base ref"作为整份报告返回（fork 无法向用户提问）；删掉按文件时间判断计划新旧的规则 —— 访谈后只要有一次 `git pull`，正确的计划就会被拒。
- `worktree`：`git check-ignore -q .worktrees` 在目录尚不存在时**必然返回 1**（带尾斜杠的模式只匹配目录），这个自称承重的闸门每次干净运行都误报，且失败分支不中止。改为探测目录内的路径并真正 `exit 1`。
- `implement`：补完成判据（全仓库唯一没有的流程型技能）；明确"请用户跑内置 `/code-review`"是请求，不能自己算作完成。
- 改名遗留：`grill-me`、`receiving-code-review` 的正文/description 仍指向已删除的 `code-review`，`tdd` 的脚注加注说明。
- 安装器：拒绝相对路径与纯空白的 `CLAUDE_SKILLS_DIR`（此前会静默装进当前目录）；`rmdir -p` 改为只回退自己创建的层级（此前会连带删掉预先存在的空目录，例如刚建好尚未写入的 `~/.claude`）；标记改为校验首行内容而非仅存在；同名**文件**（非目录）也受保护；源不可写时 canary 失效不再静默。
- CI：新增升级路径断言（9 个无标记目录 + 退役名 → 默认 exit 3 且不覆盖 → `--adopt` 后全部更新且退役名清除）、`jroot` 自身作为目标的向量、空目录残留断言；`dash -n` 此前被 `|| true` 吞掉，恒真。
- NOTICE 三处词数回填为实测值，`spec-review` 一行改为与同表一致的"上游 → 本仓库"口径；三处 `#skill-locations` 死锚点改为 `#where-skills-live` / `#how-a-skill-gets-its-command-name`；README 的写探针方向此前描述反了（描述的正是 v0.5.0 判定为 bug 的那一版），"重启会话生效"按官方文档收窄为"首次安装才需重启"。

**未采纳**：把 `.plans` 表达式的理由从三处技能里去重（技能各自独立加载，路径本身必须重复，只有理由从句可以省 —— 收益不抵可读性损失）；瘦身 `diagnosing-bugs`（1822 词确实最大，但十种复现构造是分支条件材料，推到指针后会降低它作为盲区拦截器的即时可用性）。

## 0.7.0 — 2026-07-27

第三方 Claude Code 专项审计（对比 superpowers v6.2.0 与 mattpocock plugin v1.2.0）指出的问题。全部经复现或官方文档核实后才采纳。

**Critical —— 卸载器会删掉用户自己的同名技能。** README 声称"只移除本合集的 9 个技能，你自己创建的技能不动"，实际只按目录名删除。实测：用户自己写的 `~/.claude/skills/tdd/` 被整个删除，同时脚本打印"anything else was left alone" —— 数据丢失加假陈述。现在每个安装目录写入 `.lean-skills` 标记，卸载只删带标记的；没有标记的同名目录**安装时也不覆盖**（即使 `-y`），并明确告知。CI 新增该场景断言。

**Critical —— 合并冲突可能把用户的暂存工作卷进合并提交。** 原规则「`git status --porcelain` 首列为空 = 用户的 WIP」只能识别未暂存改动。实测确认：干净开始 → 冲突 → 冲突进行中暂存了无关文件 → `git commit` 把它写进了双 parent 的合并提交，而首列是 `A` 的它不被规则识别。改为「已暂存文件 − 本次操作触及的文件」（`git diff --cached --name-only HEAD` 减去 `git diff --name-only HEAD MERGE_HEAD`），实测能正确挑出。同时区分四种操作各自的收尾命令 —— 原文统一写成"stage and commit"，而 rebase 要 `--continue`、cherry-pick 要 `--continue`、revert 要 `--continue`。
（审计原文举的"合并前就已 staged"场景，实测 git 自己会拒绝开始合并并报 exit 2；真正可复现的是冲突进行中新暂存的情形，此处按后者修。）

**`code-review` 改名为 `spec-review` 并收窄为单轴。** 官方文档：personal 层的同名技能会**替换掉内置技能**，举的例子恰好就是 `code-review`。而内置的那个自 v2.1.218 起以**独立上下文的后台子代理**运行，覆盖正确性、安全、reuse/simplification/efficiency 清理 —— 手动安装本合集等于把它顶掉，纯损失。本技能因此只保留内置做不到的那一轴：**这改动是不是当初计划要的东西**（内置不知道 `/grill-me` 的计划）。Fowler smell 基线整块删除（那是教材，且内置已覆盖），加 `context: fork` + `background: false`，1581 → 656 词。`/implement` 现在先跑 `spec-review`，再请用户跑内置 `/code-review`。

**其余修正**

- `implement` 新增第 8 步：**修完评审 finding 后重跑验证**。修一条 finding 就让第 6 步的测试/构建证据失效 —— 它们描述的是已经不存在的代码。用户可见行为要实际操作，或交给内置 `/verify`。
- `spec-review`：`BASE_SHA=$(...)` 这种写法根本不打印 SHA，而下一句要求记录字面 SHA；改为直接运行 `git merge-base` 并读它打印的值。
- `grill-me`：非 git 目录下 `$(git rev-parse --git-common-dir)` 会失败，补上退化路径（当前目录的 `.plans/`）。
- `diagnosing-bugs`：artifact 路径此前与 Phase 5/6 的"重跑原始复现"互相矛盾，补上该路径独有的完成条件（回归测试通过 + 修复覆盖 artifacts 显示的每个症状 + 报告注明未在线复验）。
- `verification-before-completion`：补一句 —— 用户可见行为的绿色测试只证明测试通过，不证明功能可用；实际操作它，或用内置 `/verify`。
- README：**斜杠菜单的说明此前是错的** —— `disable-model-invocation` 不隐藏菜单，九个技能全部出现在 `/` 里；要隐藏得另加 `user-invocable: false`。冒烟测试据此更正。
- README：**不再建议修改 superpowers 插件 cache 里的 `hooks.json`** —— 那是托管目录，更新会覆盖；改为在 `/plugin` 界面禁用。
- README："手动技能零上下文成本"改为"description 不进上下文，正文在调用时才加载"；与 mattpocock 的关系从"重名"更正为"语义重叠"（插件技能有命名空间，不会真的撞名）；补插件模式的 `/lean-skills:*` 命令写法。

**未采纳**：改用 plugin-only 发行（手动安装对不想装插件的用户仍有价值，且改名后不再顶掉任何内置技能，两种模式的命令名现在都能用）；给三个技能加 `user-invocable: false`（它们都还算合理的手动动作，隐藏菜单收益不抵可发现性损失——需要的人可自行加）。

## 0.6.0 — 2026-07-27

**`/grill-me` 现在产出书面计划。** 此前它止于"我们聊明白了"，会话一结束决策就蒸发。真正的代价不止是没记录 —— **`code-review` 的 Spec 轴因此在本地开发中长期空转**：它按顺序找 spec（用户给的路径 → commit 里的 issue 号 → `docs/`/`specs/` 下的文件），一次典型的本地开发这些一个都不存在，于是整个 Spec 子代理被跳过，三轴评审退化成两轴。

计划文档一次接通三条轨道：`implement` 照着建、`verification-before-completion` 逐条核对交代、`code-review` 的 Spec 轴终于有 spec 可对（Out of scope 一节让范围蔓延在评审里现形）。

- `grill-me`：新增计划模板（Problem / Decisions 附理由 / Seams / Out of scope / Open questions），默认落 `.plans/`，走 `.git/info/exclude` 不脏 git status，**不自动提交**。完成判据升级为可检查：每条已决分支出现在 Decisions 且带理由、每条延后分支出现在 Open questions、文件已写、用户确认与共识一致
- `implement`：第 1 步读计划（没有且改动不小则建议先 grill）；接缝取自计划；第 7 步把计划作为 spec 传给 code-review；新增计划漂移出口——实现中发现决策有误，与用户修订计划而不是默默改建别的
- `code-review`：spec 发现顺序把 `/grill-me` 的计划提到第 2 位（本地开发通常是唯一存在的 spec）；Spec brief 显式对照 Out of scope 查范围蔓延
- `verification-before-completion`：需求行改为"逐条对照计划或 spec，每条决策落到代码或标注延后"；完成判据补一句——测试通过只证明代码能跑，不证明它是被要求的那个代码

理由写进 Decisions 是刻意的：没有理由的决策清单，下周的读者（包括我自己）会把已经定下的问题重新吵一遍。

### 两名独立审计员复审后的修正（发布前，全部经复现验证）

**Critical —— 我自己推荐的流程会打断我自己刚建的机制。** README 把"`/grill-me` → `/worktree` → `/implement`"定为大改动的推荐路径，而计划默认写在 `.plans/`（未跟踪 + exclude）。实测：**未跟踪文件不进 linked worktree，exclude 规则却会跟进去**。于是 worktree 里找不到计划，`implement` 会让用户把刚做完的访谈重做一遍，`code-review` 落回后续项最终跳过 Spec 子代理 —— 正是本版要修的空转，在官方推荐路径上原样复发。修法是一条通吃的表达式：**`$(git rev-parse --git-common-dir)/../.plans`**，在主检出和 worktree 里都指向主检出，同时把此前散落四处的 `.plans/` 默认值收敛成一条规则。

- `code-review`：计划命中加硬判据（slug/标题匹配当前分支或特性、修改时间不早于基点提交；命中多个或都不匹配就问）—— 一份上周为别的特性写的陈旧计划会产出一整批言之凿凿的假发现，比没有 spec 更糟。issue 引用**放回计划之前**：tracker 是共享且权威的。（上一版把 issue 从第 1 位降到第 3 位是未记录的行为变更，此处一并纠正。）
- `grill-me`：完成判据补上 **Seams to test** 与 **Out of scope** —— 这两节分别是 `implement` 和 `code-review` 的实际依赖，此前可以整节空着仍判定"做完"；再补一条零上下文可读性检查（写"照讨论执行"不算决策）。落盘补幂等 exclude、非 git 目录、同名文件已存在三种情形。
- `implement`：第 6 步前**重读计划** —— 长任务跑到中途上下文被压缩，计划就没了，后面"每条决策都有交代"和"把计划传给 code-review"全部落空。恢复被误删的"手动技能你调不到"护栏，措辞统一为"请用户运行"。
- `resolving-merge-conflicts` **升为常驻**，并修好一处照做会出错的机制：原文让用 `git stash list` / `ORIG_HEAD` 找出合并前就脏的文件，实测这两者产不出该清单（用户没 stash 时 `stash list` 为空，`ORIG_HEAD` 只是个 SHA），而完成判据却依赖这个产不出的输入。改用 `git status --porcelain` 的两列语义：**第一列为空 = 仅工作区改动 = 用户的未提交工作**。升常驻的理由：冲突不是用户"想调技能"的时刻，是模型 `git pull` 之后自己撞上的时刻 —— 盲区触发，333 词最瘦，误触发率近乎为零，而失效后果（把用户 WIP 卷进合并提交）不可逆。
- `worktree`：新增 Step 3 拆解 —— worktree 和计划都被 exclude，**永远不出现在 `git status` 里**，堆积无人提醒。同时删掉 baseline 段落的逐字重复（0.5.0 的 CHANGELOG 声称"统一为一处"，实为加了新的没删旧的 —— 此处订正该说法）。
- README：新增装完的冒烟测试、单个技能的关闭方法；如实说明 **`code-review` 常驻靠的是编排可达性、不是盲区**（它的触发条件全部由用户发起）；"基线先绿"改为"基线先跑"。

**未采纳**：新增"不可逆动作确认闸门"技能（Claude Code 的权限系统已在工具层拦截破坏性命令；但审计指出的 `PreToolUse` hook 思路成立 —— 本合集反对的是 SessionStart 全文注入，不是 hook 机制本身，这一点此前表述过宽）；瘦身 `tdd` 并删除 `tests.md`/`mocking.md`（它是手动技能，零常驻成本，用户敲 `/tdd` 时要的正是完整参考；代价是 DOCTRINE 的否定式条款对两个上游执行了不同标准，如实记在此）；CI 里加触发 eval（需要凭据且非确定性，会让 CI 变脆——但这仍是本合集最大的未验证项）。

## 0.5.1 — 2026-07-27

补上审计里唯一漏改的一条，以及由此牵出的一个平台事实：

- `install.sh`：`CLAUDE_SKILLS_DIR` **设了但为空**时报错退出（exit 2），不再静默回落到 `$HOME/.claude/skills` —— 调用者显然想覆盖默认值，回落等于写进他正要绕开的目录。未设置时行为不变。
- `install.ps1`：**不加**这条守卫。Windows 会直接丢弃空值环境变量，`Test-Path Env:\` 与 `[Environment]::GetEnvironmentVariable` 都报不存在 —— 该状态在此平台不可表达，守卫会是不可达的死代码。CI 反过来断言这个平台事实成立，一旦哪天 Windows 变了，测试会提醒补上守卫。
- `receiving-code-review`：把领头词 **YAGNI** 写回正文。实质检查（先 grep 调用者，没人调就是删而不是补）一直都在，但改写时把这个强预训练锚点丢了 —— 按 DOCTRINE 的"领头词"一节，这是净损失，且让 NOTICE 里"保留 YAGNI 检查"的说法难以被读者验证。

## 0.5.0 — 2026-07-27

三名独立审计员（技能正文 / 安装器与 CI / 文档真实性）并行审查 `0955dd5` 后的修复。全部指控经复现验证后才采纳。

**Critical — 数据丢失，已复现后修复**

- 安装器守卫在 Windows 上可被链接绕过。`GetFullPath` 归一化 8.3 短名却不解析 reparse point，而路径解析只处理最末一级、只解一层。用指向仓库的 junction 作 `CLAUDE_SKILLS_DIR`，`-Uninstall` 会**静默删光仓库 `skills/` 下全部 11 个文件并报告成功**（已在克隆上复现）。

改用两层守卫：前缀比较（免费、双向）+ **canary 上溯**——把标记文件写进**源目录**，再从目标逐级向上，问文件系统每一层能否看到它。读操作会穿透 junction 与符号链接，所以这既能识别"目标就是源"，也能识别"目标落在源内部"。

修复过程本身出过两次错，都由更严格的验证抓出：

1. Windows PowerShell 5.1 的 `New-Item` **没有 `-LiteralPath`**，第一版修复在探针那行直接抛异常。我本地的 junction 矩阵因此**假通过**——测试只检查"是否抛异常"，而异常来自崩溃不是守卫。CI 的 Windows 腿把它挡了下来。改用 `[IO.File]::WriteAllText` / `[IO.Directory]::CreateDirectory`（天然字面，且不把路径里的 `[ ]` 当通配符）。
2. 断言改严（必须匹配 `refusing:` 才算拦截）之后，暴露出**探针方向本身是错的**：当 junction 在**父组件**上（`link→skills` 用作 `link/sub`），标记写进的是子目录，源目录里查不到，9 个技能被装进了 `skills/sub`。这才有了上面的 canary 反向上溯方案。

最终 16 个向量（直指、仓库根、junction 指根、junction 指 skills、链式 junction、父组件 junction 深 1 级与深 2 级、多级不存在路径 × 安装/卸载）全部拒绝，源完好、零残留、canary 不残留；含空格与方括号的正常目标仍安装正常。POSIX 侧 `pwd -P` 本就解析符号链接，同样补上 canary 以求两端等价。

**Important**

- 安装器：拒绝时的清理改为逐级回退（原先 `Remove-Item` 无 `-Recurse`，多级路径会在源码树里留残骸）；源目录列表在创建目标前快照（避免目标被当成第 10 个技能自我复制）；复制改为先落临时目录再原子换名（中断不再让技能整个消失）；参数解析改为循环（`-y --uninstall` 原先静默执行安装）
- `resolving-merge-conflicts`：`git add -A` 收窄到本次合并涉及的文件——原先会把用户无关的未提交改动卷进合并提交
- `implement`：`BASE_SHA=$(...)` 这种 shell 变量记录法在下一条命令就失效，与 code-review 自己"永远用字面 SHA"的规则自相矛盾；改为运行后把**打印出的 SHA** 写进笔记与报告
- `worktree`：`.git/info/exclude` 字面路径在子模块（`.git` 是文件）和子目录下必然失败且不中断，会产出未被忽略的 worktree；改走 `git rev-parse --git-common-dir` 并要求 `check-ignore` 确认后才建
- `code-review`：子代理拿不到主代理的上下文，而 brief 从未包含第 2 步找到的 spec 内容和第 3 步的标准文件清单；两处补齐。PR 编号不是 ref，补 `gh pr checkout` 前置
- `diagnosing-bugs`：artifact loop 的进入闸门原先只有一句"穷尽以上"，无举证要求，构成绕开建复现回路的逃生舱；改为必须逐条写出 1–10 号构造法为何不适用，并为该路径显式豁免 Phase 2
- CI：补 junction/符号链接向量（链式、父组件是链接、深两级）、`git status` 洁净断言、退出码须为 2 且**必须含 `refusing:` 报文**（只断言"非零退出"会把崩溃误判为拦截，这正是上面第 1 条假通过的成因）、外来技能存活断言、全文件数（非仅 SKILL.md）断言、diff 配方与 SKILL.md 的文本锚点绑定、npm 钉版本并回显错误、`concurrency` 与 `timeout-minutes`

**Minor**

- `diagnosing-bugs` 的 "artifact loop below" 方向写反（该节在上方）；脚注补齐 artifact loop 与 description 改动
- "green baseline" 一个意思三处两义，统一为"基线先跑、结果如实报告，是否继续由用户定"
- `worktree` 把 `Cargo.toml`/`go.mod` 称作 lockfile；原生工具举例中的 `/worktree` 与本技能自身撞名
- `receiving-code-review` 第 5 步"回应"排在第 6 步"实施"之前，但示例回应只能在实施后说出；两步合并
- `resolving-merge-conflicts` 是唯一没有完成判据的技能，补上
- `implement` 的 `(/worktree carries...)` 对执行者是死文本，改为面向用户的指路
- CHANGELOG 的 "0.3.1" 从未存在于任何 manifest（`81c27ae` 处自报 0.3.0），改标为"0.3.0 后续修补"；CI 矩阵的归属提交更正为 `3fe3ce3`
- NOTICE 补 `resolving-merge-conflicts` 的 description 重写记录；"退化为仅 code smells"表述收窄为"仅剩 Standards 轴"

**未采纳**：`Resolve-Physical` 改用 P/Invoke `GetFinalPathNameByHandle`（写探针是文件系统事实，比路径规范化更强且不需要运行时编译）、按组件递归解析链接（同上）、四常驻技能的行为 eval（需模型在环的评测框架，仍挂在"无法验证"）。

## 0.4.0 — 2026-07-27

外部审计（基于 `f53c68a`）逐条核实后的采纳与自查修复：

- **code-review**：新增 **Correctness/Risk 第三轴**——无 spec 时不再退化为仅 code smells；发现按严重度标注，报告以跨轴 **Triage** 列表收尾（Critical → Important → Minor）；diff 改为**快照文件**，全部子代理共读同一份内容（同时根除 `$BASE` 不跨 shell 的隐患）；纯 WIP 请求（"审我未提交的改动"）默认 fixed point = `HEAD`，少问一次没有决策价值的问题
- **implement**：开工前记录 `BASE_SHA` 作为审查基点——原地修改（不开分支）也有明确起点
- **worktree**：忽略改走 `.git/info/exclude`，不再动 tracked 文件，"是否提交 .gitignore"的问题整个消失；依赖安装按锁文件 / `packageManager` 字段检测包管理器（pnpm/yarn/bun/npm、uv/poetry/pdm/pip），检测不出就问而不是瞎装；补分支或 worktree 已存在的处理
- **diagnosing-bugs**：新增 **artifact loop**——无法复跑的真实故障（日志、trace、core dump、HAR、崩溃报告）用证据回路证伪假设；仍需回归测试，且报告必须声明"按证据验证而非活复现"
- **tdd**：脚注注明 Red→Green（重构后置于评审段）是上游有意变体
- **安装器**：源/目标路径守卫——目标等于或位于仓库自身 `skills/` 内时直接拒绝（原先会先删源再复制失败）；新增 `--uninstall` / `-Uninstall`，只移除本合集的 9 个技能
- **CI**：checkout 按 commit SHA 固定；新增 diff 配方夹具测试（committed / staged / unstaged / untracked / deleted / renamed / 含空格文件名七类全覆盖断言）；安装器守卫与卸载往返测试；官方 `claude plugin validate --strict`
- **元数据**：GitHub description 同步为 4 resident；上游 mattpocock 固定到精确 commit（`ed37663`）；新增本文件、git tag 与 GitHub Release

审计中拒绝或压缩的项及理由，见对应 PR/commit 说明：临时目录+原子替换+备份机制（超出文本安装器的复杂度收益比）、8 步包管理器探测链（压缩为锁文件+packageManager+询问）、worktree 六项边界枚举（模型原生处理 git 报错，只保留两项真实高频）、四常驻技能行为 eval（需模型在环的评测框架，超出本仓库范围）、finding 固定 JSON schema（散文技能保留要素即可）。

## 0.3.0 后续修补 — 2026-07-26（`81c27ae`，未单独发版，manifest 版本号仍为 0.3.0）

- code-review：子代理改收字面 SHA（`$BASE` 不跨 shell）；merge-base 失败显式停下而非静默降级；无关 WIP 可退回 committed-only；worktree 的 .gitignore 是否提交交还用户

## 0.3.0 — 2026-07-26（`f53c68a`）

- 常驻 7 → 4：入场券改为"盲区触发 + 护栏而非教材"双重测试；tdd / worktree / resolving-merge-conflicts 降手动
- 修四缺陷：worktree `$BRANCH` 未定义；code-review 审不到 WIP；`--abort` 绝对禁令放宽；implement 无条件 commit 改为经授权
- implement 不再跨层调用手动技能，改为内联一句话护栏
- README 写明适用边界：交互式会话 + 强模型；无人值守长任务适合 superpowers 式流程

## 0.2.0 — 2026-07-26（`8d5957f`）

- 修复编排不可达：implement 调用的 worktree / receiving-code-review 当时是手动技能，模型调不到——按官方 `disable-model-invocation` 语义翻为常驻（该决定在 0.3.0 被更好的内联方案取代）
- NOTICE 词数改为实测值
- CI 三平台矩阵上线（`3fe3ce3`，在 0.2.0 版本号期间加入，晚于 `8d5957f`）

## 0.1.0 — 2026-07-26（`e8b9a66`）

- 首发：9 技能（5 常驻 / 4 手动），双安装脚本，DOCTRINE / NOTICE / 双上游 MIT 归属


---

发布清单在 [README 的「维护」一节](README.md#发布清单)，那是唯一的一份。（0.10.0 之前它是本文件末尾的一段附录；0.10.0 的记录说它"从 0.9.1 的变更记录里搬走"，两点都不对——它从来不在任何一个版本条目里，而且直到 0.11.0 才真的移走。）
