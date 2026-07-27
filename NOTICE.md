# 归属与改动记录

本合集是衍生作品。上游两个仓库均为 MIT 许可，完整许可证文本见
[`LICENSE-mattpocock`](LICENSE-mattpocock) 和 [`LICENSE-superpowers`](LICENSE-superpowers)。

- [mattpocock/skills](https://github.com/mattpocock/skills) — MIT © 2026 Matt Pocock
- [obra/superpowers](https://github.com/obra/superpowers) — MIT © 2025 Jesse Vincent

参照的上游版本：mattpocock/skills `main` @ `ed37663cc5fbef691ddfecd080dff42f7e7e350d`（2026-07-26 克隆），superpowers `v6.2.0`。

## 逐文件

| 本仓库文件 | 上游 | 改动 |
|---|---|---|
| `skills/tdd/SKILL.md` | mattpocock `engineering/tdd` | 正文未动（仅署名脚注）；0.3.0 起设为用户调用，description 改为人读式一行；0.4.0 脚注注明 Red→Green（重构后置于评审段）是上游有意变体而非疏漏 |
| `skills/tdd/tests.md` | 同上 | 无 |
| `skills/tdd/mocking.md` | 同上 | 无 |
| `skills/resolving-merge-conflicts/SKILL.md` | mattpocock `engineering/resolving-merge-conflicts` | 加标题与署名，description 改为人读式一行；0.3.0 放宽 `--abort` 绝对禁令（因难而逃仍禁止，合并本身是错误时允许中止并说明理由），并设为用户调用；0.4.0 新增完成判据，并把 `git add -A` 收窄到本次合并涉及的文件（原文会把用户无关的 WIP 卷进合并提交）；0.6.0 改为模型调用（冲突是撞上的、不是想调技能的时刻），description 换成触发式，并把"合并前就脏的文件"从产不出结果的 `git stash list`/`ORIG_HEAD` 改为 `git status --porcelain` 的两列语义；0.7.0 进一步改为「已暂存文件 − 本次操作触及的文件」（两列语义漏掉冲突进行中新暂存的文件，实测会被卷进合并提交），并区分 merge/rebase/cherry-pick/revert 各自的收尾命令 |
| `skills/diagnosing-bugs/SKILL.md` | mattpocock `engineering/diagnosing-bugs` | 加入「第二次尝试规则」（思路取自 superpowers `systematic-debugging`）；移除对 `scripts/hitl-loop.template.sh` 的路径依赖，改为通用描述；移除对本合集之外技能的交接指向；0.3.0 将 description 收窄至硬 bug / 性能回归 / 修过未愈（正文自我定位本就是 hard bugs）；0.4.0 新增 artifact loop —— 无法复跑的真实故障（日志/trace/core dump/HAR）用证据回路证伪假设，仍需回归测试并声明"按证据验证而非活复现" |
| `skills/spec-review/SKILL.md` | mattpocock `engineering/code-review` | issue tracker 查找不再要求先跑 `setup-matt-pocock-skills`，改为直接用 `gh`/tracker CLI，找不到则询问；标准来源增列 `CLAUDE.md`/`AGENTS.md`；0.3.0 修复 WIP 盲区 —— diff 锚定 merge-base 对工作区（含未提交改动），untracked 文件经 `git status` 纳入（上游三点 diff 的 description 承诺审 WIP 但机制看不见它，属上游原生缺陷）；0.4.0 起显著偏离上游 —— 新增 Correctness/Risk 第三轴（上游无 spec 时只剩 Standards 轴，仓库无文档化标准时即退化为纯 smell 基线）、按严重度 Critical/Important/Minor 跨轴分诊（上游禁止 rerank，本仓库改为分轴分析 + 严重度行动序）、diff 改为快照文件供全部子代理共读、纯 WIP 请求默认 fixed point = HEAD；0.6.0 spec 发现顺序纳入 `/grill-me` 的计划（含匹配判据，防陈旧计划误用），Spec brief 对照 Out of scope 查范围蔓延；0.7.0 **改名 `code-review` → `spec-review` 并收窄为单轴** —— personal 层同名技能会替换 Claude Code 内置 `/code-review`（该内置自 v2.1.218 起以独立上下文的后台子代理运行，覆盖正确性/安全/清理），顶掉它是纯损失；本技能只保留内置做不到的"是否符合当初的计划"，并加 `context: fork` / `background: false`；上游 1060 → 本仓库 742 词（本仓库 0.6.0 版曾达 1581 词）|
| `skills/grill-me/SKILL.md` | mattpocock `productivity/grill-me` + `productivity/grilling` | 两个技能合并为一个用户调用技能；新增完成判据；0.6.0 新增书面计划产出（模板 + `$(git rev-parse --git-common-dir)/../.plans` 落盘位置 + 覆盖五节的判据）—— 上游靠 `to-spec` 与 issue tracker 持久化决策，本合集不要求这些外部依赖 |
| `skills/implement/SKILL.md` | mattpocock `engineering/implement` | 0.3.0 重写：内联 tdd/worktree 的一句话护栏（模型调不到手动技能，不再跨层调用）；commit 从无条件改为经用户授权；新增验证步骤与转向 `diagnosing-bugs` 的出口；0.4.0 开工前记录 `BASE_SHA` 作为审查基点；0.6.0 第 1 步读 `/grill-me` 的计划作为 spec、第 6 步前重读计划、新增计划漂移出口 |
| `skills/verification-before-completion/SKILL.md` | superpowers `verification-before-completion` | 重写。保留 gate 的实质和证据对照表；按 DOCTRINE 的正向表述与修剪规则改写，删去 Red Flags / Rationalization 两节（大量否定式表述）；556 → 442 词；0.6.0 需求行改为逐条对照计划或 spec |
| `skills/receiving-code-review/SKILL.md` | superpowers `receiving-code-review` | 重写。保留"先核实再实施 / 先澄清全部再动手 / 用技术理由反驳 / YAGNI 检查"；删去 obra 个人语境（"your human partner"）和禁止致谢的段落；894 → 428 词。0.2.0 起由用户调用改为模型调用（`implement` 需要够到它，且触发点在模型盲区），description 换成触发式写法 |
| `skills/worktree/SKILL.md` | superpowers `using-git-worktrees` | 精简并改名（`using-git-worktrees` → `worktree`）；保留检测顺序、submodule 守卫、原生工具优先、gitignore 校验、基线测试；1064 → 720 词。0.2.0 曾改为模型调用；0.3.0 回到用户调用（`implement` 改为内联护栏后不再需要模型侧可达），补上分支命名规则（修复 `$BRANCH` 未定义）；0.6.0 新增 Step 3 拆解、删除 baseline 段落的逐字重复；0.4.0 忽略改走 `.git/info/exclude`（不动 tracked 文件，取代"是否提交 .gitignore"问题）、依赖安装按锁文件/`packageManager` 检测包管理器、补分支/worktree 已存在的处理 |
| `DOCTRINE.md` | mattpocock `productivity/writing-great-skills` | 翻译为中文并浓缩；术语沿用原文 |

## 未收录

上游的其余技能不在本合集内，原因见 [README](README.md#收录标准) 的三条收录标准。若需要它们，直接从上游仓库取用。
