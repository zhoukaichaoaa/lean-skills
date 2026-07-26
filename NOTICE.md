# 归属与改动记录

本合集是衍生作品。上游两个仓库均为 MIT 许可，完整许可证文本见
[`LICENSE-mattpocock`](LICENSE-mattpocock) 和 [`LICENSE-superpowers`](LICENSE-superpowers)。

- [mattpocock/skills](https://github.com/mattpocock/skills) — MIT © 2026 Matt Pocock
- [obra/superpowers](https://github.com/obra/superpowers) — MIT © 2025 Jesse Vincent

参照的上游版本：mattpocock/skills `main`（2026-07 克隆），superpowers `v6.2.0`。

## 逐文件

| 本仓库文件 | 上游 | 改动 |
|---|---|---|
| `skills/tdd/SKILL.md` | mattpocock `engineering/tdd` | 正文未动（仅署名脚注）；0.3.0 起设为用户调用，description 改为人读式一行 |
| `skills/tdd/tests.md` | 同上 | 无 |
| `skills/tdd/mocking.md` | 同上 | 无 |
| `skills/resolving-merge-conflicts/SKILL.md` | mattpocock `engineering/resolving-merge-conflicts` | 加标题与署名；0.3.0 放宽 `--abort` 绝对禁令（因难而逃仍禁止，合并本身是错误时允许中止并说明理由），并设为用户调用 |
| `skills/diagnosing-bugs/SKILL.md` | mattpocock `engineering/diagnosing-bugs` | 加入「第二次尝试规则」（思路取自 superpowers `systematic-debugging`）；移除对 `scripts/hitl-loop.template.sh` 的路径依赖，改为通用描述；移除对本合集之外技能的交接指向；0.3.0 将 description 收窄至硬 bug / 性能回归 / 修过未愈（正文自我定位本就是 hard bugs）；1380 → 1474 词 |
| `skills/code-review/SKILL.md` | mattpocock `engineering/code-review` | issue tracker 查找不再要求先跑 `setup-matt-pocock-skills`，改为直接用 `gh`/tracker CLI，找不到则询问；标准来源增列 `CLAUDE.md`/`AGENTS.md`；0.3.0 修复 WIP 盲区 —— diff 锚定 merge-base 对工作区（含未提交改动），untracked 文件经 `git status` 纳入（上游三点 diff 的 description 承诺审 WIP 但机制看不见它，属上游原生缺陷） |
| `skills/grill-me/SKILL.md` | mattpocock `productivity/grill-me` + `productivity/grilling` | 两个技能合并为一个用户调用技能；新增完成判据 |
| `skills/implement/SKILL.md` | mattpocock `engineering/implement` | 0.3.0 重写：内联 tdd/worktree 的一句话护栏（模型调不到手动技能，不再跨层调用）；commit 从无条件改为经用户授权；新增验证步骤与转向 `diagnosing-bugs` 的出口 |
| `skills/verification-before-completion/SKILL.md` | superpowers `verification-before-completion` | 重写。保留 gate 的实质和证据对照表；按 DOCTRINE 的正向表述与修剪规则改写，删去 Red Flags / Rationalization 两节（大量否定式表述）；556 → 367 词 |
| `skills/receiving-code-review/SKILL.md` | superpowers `receiving-code-review` | 重写。保留"先核实再实施 / 先澄清全部再动手 / 用技术理由反驳 / YAGNI 检查"；删去 obra 个人语境（"your human partner"）和禁止致谢的段落；894 → 409 词。0.2.0 起由用户调用改为模型调用（`implement` 需要够到它，且触发点在模型盲区），description 换成触发式写法 |
| `skills/worktree/SKILL.md` | superpowers `using-git-worktrees` | 精简并改名（`using-git-worktrees` → `worktree`）；保留检测顺序、submodule 守卫、原生工具优先、gitignore 校验、基线测试；1064 → 412 词。0.2.0 曾改为模型调用；0.3.0 回到用户调用（`implement` 改为内联护栏后不再需要模型侧可达），并补上分支命名规则（修复 `$BRANCH` 未定义） |
| `DOCTRINE.md` | mattpocock `productivity/writing-great-skills` | 翻译为中文并浓缩；术语沿用原文 |

## 未收录

上游的其余技能不在本合集内，原因见 [README](README.md#收录标准) 的三条收录标准。若需要它们，直接从上游仓库取用。
