# 归属与改动记录

本合集是衍生作品。上游两个仓库均为 MIT 许可，完整许可证文本见
[`LICENSE-mattpocock`](LICENSE-mattpocock) 和 [`LICENSE-superpowers`](LICENSE-superpowers)。

- [mattpocock/skills](https://github.com/mattpocock/skills) — MIT © 2026 Matt Pocock
- [obra/superpowers](https://github.com/obra/superpowers) — MIT © 2025 Jesse Vincent

参照的上游版本：mattpocock/skills `main` @ `ed37663cc5fbef691ddfecd080dff42f7e7e350d`（2026-07-26 克隆），superpowers `v6.2.0`。

## 逐文件

这张表是每个衍生文件的**唯一**逐版本改动记录。每个 `SKILL.md` 末尾的署名脚注只说它相对上游是什么（那不会每个版本变），并指回这里 —— 同一份变更日志写在两处，就会漂在两处。

词数口径：**空白分隔的词数**（`awk '{n+=NF}END{print n}' <file>`，等价于 Python 的 `len(text.split())`）。不用 `wc -w` —— 它的结果随 locale 变（同一份 `worktree/SKILL.md` 在 `LC_ALL=C` 下是 851、在 UTF-8 locale 下是 877），BSD 与 GNU 的实现又各不相同，写进文档就无法复核。箭头两侧一律用上面这个口径，上游数字取自本文件顶部钉住的那两个提交。CI 会对每个箭头的右侧重算并比对。

| 本仓库文件 | 上游 | 改动 |
|---|---|---|
| `skills/tdd/SKILL.md` | mattpocock `engineering/tdd` | 正文未动（仅署名脚注）；0.3.0 起设为用户调用，description 改为人读式一行；0.4.0 脚注注明 Red→Green（重构后置于评审段）是上游有意变体而非疏漏；0.8.0 脚注加注说明 `code-review` 已改名 |
| `skills/tdd/tests.md` | 同上 | 无 |
| `skills/tdd/mocking.md` | 同上 | 无 |
| `skills/resolving-merge-conflicts/SKILL.md` | mattpocock `engineering/resolving-merge-conflicts` | 加标题与署名，description 改为人读式一行；0.3.0 放宽 `--abort` 绝对禁令（因难而逃仍禁止，合并本身是错误时允许中止并说明理由），并设为用户调用；0.4.0 新增完成判据，并把 `git add -A` 收窄到本次合并涉及的文件（原文会把用户无关的 WIP 卷进合并提交）；0.6.0 改为模型调用（冲突是撞上的、不是想调技能的时刻），description 换成触发式，并把"合并前就脏的文件"从产不出结果的 `git stash list`/`ORIG_HEAD` 改为 `git status --porcelain` 的两列语义；0.7.0 进一步改为「已暂存文件 − 本次操作触及的文件」（两列语义漏掉冲突进行中新暂存的文件，实测会被卷进合并提交），并区分 merge/rebase/cherry-pick/revert 各自的收尾命令；0.8.0 “操作触及的文件”改从 merge-base 起算（`git diff HEAD MERGE_HEAD` 含本侧改动，会把用户编辑过的文件误判成合并自己的），并新增“解决前先 `git restore --staged`”这一步（此前只声明合并提交会带走整个索引，却没给纠正动作）；0.8.1 三类用户文件分开、只 restore staged；0.9.0 合并范围从 merge-base 起算且禁用命令替换、`--name-status -M` 认重命名、`core.quotePath=false` 防转义、完成判据覆盖全部产生的提交；0.9.2 完成范围的边界改为按操作在第 1 步各自记录（`ORIG_HEAD` 单次 cherry-pick 根本不设、rebase 的又含新 base 上原有提交），新增第 9 步对用户路径直接取证；0.10.0 preamble 点名两种塌陷形状（塌成空、塌成第一个），操作表补 `git am` 与"四者皆无"（`stash pop` / `apply --3way`）两支，`MERGE_HEAD` 按文件逐行读并取并集（octopus 下 `rev-parse` 只给第一个），per-operation diff 用 `^<n>` 显式主线，第 9 步 pathspec 加 `:(top)`、merge 按 `%P` 列全部父提交；0.11.0 新增第三种形状（报错指错原因）与 rebase 专属的 `git stash push` 步骤、操作表给出自上而下的读取顺序（`rebase -r` 会同时留下 `MERGE_HEAD` 与 `rebase-merge/`）、`merge-base --all`（交叉合并有多个 base，各自算出的文件清单不同）、第 9 步每个路径一个 `:(top)` 参数、`--diff-merges=first-parent`（merge 提交在 `--name-only` 下不列任何文件）、含空格路径改用 `--porcelain -z`（`core.quotePath` 只管非 ASCII）；0.12.0 rebase 的停靠改为 `git stash push -u`（第 4 步刚把文件移出索引，新建文件因此变成 untracked，裸 `push` 会被它整条打掉），并说明 `pop` 回来是未暂存/未跟踪而非恢复失败；0.12.1 脚注不再重复逐版本日志，改为只说相对上游是什么并指回本文件 |
| `skills/diagnosing-bugs/SKILL.md` | mattpocock `engineering/diagnosing-bugs` | 加入「第二次尝试规则」（思路取自 superpowers `systematic-debugging`）；移除对 `scripts/hitl-loop.template.sh` 的路径依赖，改为通用描述；移除对本合集之外技能的交接指向；0.3.0 将 description 收窄至硬 bug / 性能回归 / 修过未愈（正文自我定位本就是 hard bugs）；0.4.0 新增 artifact loop —— 无法复跑的真实故障（日志/trace/core dump/HAR）用证据回路证伪假设，仍需回归测试并声明"按证据验证而非活复现"；0.5.0 artifact loop 加入进入判据（十种复现构造逐条写出为何不成立）并贯穿到 Phase 2；0.7.0 修复阶段的回归验证在 artifact 路径上改为逐件对照证据；0.9.0 `[DEBUG-a4f2]` 在 `grep` 里是字符类，清理命令改为 `grep -rF`；0.10.0 更正 `grep` 退出码语义（无匹配是 1，2 是出错） |
| `skills/spec-review/SKILL.md` | mattpocock `engineering/code-review` | issue tracker 查找不再要求先跑 `setup-matt-pocock-skills`，改为直接用 `gh`/tracker CLI，找不到则询问；标准来源曾增列 `CLAUDE.md`/`AGENTS.md`（0.7.0 收窄为单轴时随 Standards 轴一并移除）；0.3.0 修复 WIP 盲区 —— diff 锚定 merge-base 对工作区（含未提交改动），untracked 文件经 `git status` 纳入（上游三点 diff 的 description 承诺审 WIP 但机制看不见它，属上游原生缺陷）；0.4.0 起显著偏离上游 —— 新增 Correctness/Risk 第三轴（上游无 spec 时只剩 Standards 轴，仓库无文档化标准时即退化为纯 smell 基线）、按严重度 Critical/Important/Minor 跨轴分诊（上游禁止 rerank，本仓库改为分轴分析 + 严重度行动序）、diff 改为快照文件供全部子代理共读、纯 WIP 请求默认 fixed point = HEAD；0.6.0 spec 发现顺序纳入 `/grill-me` 的计划（含匹配判据，防陈旧计划误用），Spec brief 对照 Out of scope 查范围蔓延；0.7.0 **改名 `code-review` → `spec-review` 并收窄为单轴** —— personal 层同名技能会替换 Claude Code 内置 `/code-review`（该内置自 **Claude Code** v2.1.218 起以独立上下文的后台子代理运行，覆盖正确性 bug 与 reuse/simplification/efficiency 清理；安全属 `/security-review`），顶掉它是纯损失；本技能只保留内置做不到的"是否符合当初的计划"，并加 `context: fork` / `background: false`；0.8.0 删掉“内置 `/code-review` 覆盖安全”的错误说法（它曾指挥 fork 子代理主动跳过安全审查）、补 `argument-hint` 与 `$ARGUMENTS`（fork 子代理拿不到调用方上下文）、删掉按文件时间判断计划新旧的规则；0.8.1 修正 WIP 分类；0.8.2 发现 `baseRefName` 是分支名而非可用 ref（当时引入的 `baseRepository` 字段并不存在，0.9.0 改掉）；0.9.0 重写基线解析（`baseRefOid`、默认分支不猜、禁用 `@{upstream}`）；0.9.2 `ls-remote` 只问不取，补 `git fetch` 与 `cat-file -e` 复查，且 `gh` 失败不再当作"没有 PR"；0.10.0 `ls-remote --symref` 提到 `symbolic-ref` 之前（`refs/remotes/origin/HEAD` 只在 clone 时写一次，`fetch` 从不刷新），`.plans` 补子模块与非仓库两种回退。上游 1104 → 本仓库 1326 词（本仓库 0.6.0 版曾达 1642 词）|
| `skills/grill-me/SKILL.md` | mattpocock `productivity/grill-me` + `productivity/grilling` | 两个技能合并为一个用户调用技能；新增完成判据；0.6.0 新增书面计划产出（模板 + `$(git rev-parse --git-common-dir)/../.plans` 落盘位置 + 覆盖五节的判据）—— 上游靠 `to-spec` 与 issue tracker 持久化决策，本合集不要求这些外部依赖；0.8.0 清理改名遗留（正文仍指向已删除的 `code-review`）；0.9.0 `.plans` 路径表达式加引号（含空格的 worktree 路径下会建出垃圾目录且 exit 0） |
| `skills/implement/SKILL.md` | mattpocock `engineering/implement` | 0.3.0 重写：内联 tdd/worktree 的一句话护栏（模型调不到手动技能，不再跨层调用）；commit 从无条件改为经用户授权；新增验证步骤与转向 `diagnosing-bugs` 的出口；0.4.0 开工前记录 `BASE_SHA` 作为审查基点；0.8.0 补完成判据（当时全仓唯一没有的流程型技能），并明确“请用户跑内置 `/code-review`”是请求、不能自己算作完成；0.6.0 第 1 步读 `/grill-me` 的计划作为 spec、第 6 步前重读计划、新增计划漂移出口；0.9.0 第 3 步注明空仓库下 `git rev-parse HEAD` 会把字面 `HEAD` 打到 stdout（一个看起来完全合理的"SHA"）；0.10.0 `.plans` 补非仓库回退 |
| `skills/verification-before-completion/SKILL.md` | superpowers `verification-before-completion` | 重写。保留 gate 的实质和证据对照表；按 DOCTRINE 的正向表述与修剪规则改写，删去 Red Flags / Rationalization 两节（大量否定式表述）；580 → 465 词；0.6.0 需求行改为逐条对照计划或 spec；0.7.0 补一条：面向用户的行为上，测试全绿只证明测试通过，不证明功能可用 —— 要真去跑一遍 |
| `skills/receiving-code-review/SKILL.md` | superpowers `receiving-code-review` | 重写。保留"先核实再实施 / 先澄清全部再动手 / 用技术理由反驳 / YAGNI 检查"；删去 obra 个人语境（"your human partner"）和禁止致谢的段落；913 → 449 词。0.2.0 起由用户调用改为模型调用（`implement` 需要够到它，且触发点在模型盲区），description 换成触发式写法；0.8.0 清理改名遗留（指向已删除的 `code-review`） |
| `skills/worktree/SKILL.md` | superpowers `using-git-worktrees` | 精简并改名（`using-git-worktrees` → `worktree`）；保留检测顺序、submodule 守卫、原生工具优先、gitignore 校验、基线测试；1069 → 892 词。0.2.0 曾改为模型调用；0.3.0 回到用户调用（`implement` 改为内联护栏后不再需要模型侧可达），补上分支命名规则（修复 `$BRANCH` 未定义）；0.8.0 `git check-ignore -q <dir>` 在目录尚不存在时必然返回 1（带尾斜杠的模式只匹配目录），改为探测目录内的路径并真正 `exit 1`；0.9.0 目录名收进 `WTDIR` 变量（忽略模式、check-ignore、worktree add 三处必须同一字符串）、Step 0 增加 `--is-inside-work-tree` 前置；0.6.0 新增 Step 3 拆解、删除 baseline 段落的逐字重复；0.4.0 忽略改走 `.git/info/exclude`（不动 tracked 文件，取代"是否提交 .gitignore"问题）、依赖安装按锁文件/`packageManager` 检测包管理器、补分支/worktree 已存在的处理；0.10.0 裸仓库的判定理由改写为事实描述（此前把"两个变量恰好相等"当成原因） |
| `DOCTRINE.md` | mattpocock `productivity/writing-great-skills` | 翻译为中文并浓缩；术语沿用原文；0.9.0 「零上下文成本」改为「不花常驻 description 成本，正文在调用时进入上下文并留在会话里」 |

0.9.1 未改动上表任何文件 —— 内容是 CI 的 macOS 覆盖补齐、`platform parity` 守卫与发布清单，以及对技能正文的 macOS 兼容性静态扫描（结论：零处 GNU 专有惯用法）。列在这里，是为了让版本序列没有缺口。

## 未收录

上游的其余技能不在本合集内，原因见 [README](README.md#收录标准) 的三条收录标准。若需要它们，直接从上游仓库取用。
