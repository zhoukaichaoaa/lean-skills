# Changelog

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

**发布清单**：**标签一经推送即不可变**（发版前确认 `git ls-remote --tags origin` 里没有该标签；任何修复走新版本号，绝不 `tag -f`）→ **任何改动都要 Windows 与 macOS 双平台落地并各自有断言**（`install.sh` 与 `install.ps1` 同时改；CI 步骤默认 `if: runner.os != 'Windows'`，单平台步骤须在 `platform parity` 的豁免表里写明理由）→ 改 manifests 版本号 → **更新 NOTICE 的逐文件行并用 `wc -w` 重算词数** → 更新本文件 → 本地把 CI 的每条腿在干净克隆上原样跑一遍 → commit & push → CI 绿 → `git tag vX.Y.Z && git push --tags` → `gh release create` → 核对 GitHub description → `claude plugin validate --strict .`
