# Changelog

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

**发布清单**：改 manifests 版本号 → 更新本文件 → 本地全量验证 + 自审 → commit & push → CI 绿 → `git tag vX.Y.Z && git push --tags` → `gh release create` → 核对 GitHub description → `claude plugin validate --strict .`
