# lean-skills

[![ci](https://github.com/zhoukaichaoaa/lean-skills/actions/workflows/ci.yml/badge.svg)](https://github.com/zhoukaichaoaa/lean-skills/actions/workflows/ci.yml)

> 9 个技能。5 个常驻，4 个手动。没有强制条款，没有启动注入。
>
> A lean, context-budgeted skill set for Claude Code — distilled from mattpocock/skills and obra/superpowers. Docs in Chinese, skills in English.

从 [mattpocock/skills](https://github.com/mattpocock/skills)（41 个技能）和 [obra/superpowers](https://github.com/obra/superpowers)（14 个技能）里挑出真正抵得上上下文成本的部分，去掉重叠、去掉强制、去掉对安装脚本的依赖，合成一套可以直接用的最小集。

## 收录标准

每个技能必须通过三个问题：

1. **它防的是我哪个具体的坏习惯？** —— 答不上来就不收
2. **这个坏习惯是"不够聪明"造成的，还是"性格"造成的？** —— 前者随模型变强会自然消失，只收后者
3. **它值得每一轮都占 description 的 token 吗？** —— 不值得就设成手动调用

第 2 条是关键。模型再聪明，也照样会没跑测试就说"修好了"、凭直觉猜 bug 原因、需求没问清就开写。这三件事跟智商无关，所以对应的技能该留。反过来，那些把任务拆成极琐碎步骤、反复叮嘱"不要假装通过"的技能，是给弱模型打的补丁，今天反而会压低推理海拔。

## 技能一览

**常驻（模型自动触发，description 每轮占上下文）**

| 技能 | 防的坏习惯 | 来源 |
|---|---|---|
| `verification-before-completion` | 没跑命令就说"修好了" | superpowers，重写 |
| `receiving-code-review` | 评审说啥都点头照做 | superpowers，重写 |
| `diagnosing-bugs` | 硬 bug 不建复现回路就开猜；同一个 bug 连修两刀 | mattpocock，微调 |
| `spec-review` | 只查代码规范、不查"当初要的是什么" | mattpocock，收窄为单轴 |
| `resolving-merge-conflicts` | 冲突了就 `--abort`、随便选一边、或 `git add -A` 把你的 WIP 卷进合并提交 | mattpocock，微调 |

**手动（description 不进上下文；正文在你调用时才加载）**

| 技能 | 用途 | 来源 |
|---|---|---|
| `grill-me` | 动手前把需求追问到收敛，**并落成书面计划** | mattpocock，合并 + 扩写 |
| `implement` | 编排：读计划 → 隔离 → 测试先行 → 验证 → 评审 → 交付 | mattpocock，重写 |
| `tdd` | 测试先行的完整参考（接缝 / 反模式 / 循环规则） | mattpocock，原文 |
| `worktree` | 开隔离工作区的完整流程 | superpowers，精简 |

常驻/手动的区分用的是 Claude Code 官方字段 `disable-model-invocation`（[文档](https://code.claude.com/docs/en/skills#control-who-invokes-a-skill)）。官方语义：设为 `true` 时 **description 不进上下文、模型无法调用**，只能由你 `/名字` 触发。

> **不要与 Claude Code 内置的 `/code-review` 重名。** 官方规则：personal 层的同名技能会**替换掉内置技能**（[文档](https://code.claude.com/docs/en/skills#skill-locations) 举的例子恰好就是 `code-review`）。内置那个自 v2.1.218 起以**独立上下文的后台子代理**运行，覆盖正确性、安全与清理——顶掉它是纯损失。所以本合集把自己的评审技能改名为 `spec-review` 并收窄到内置技能唯一做不到的那一轴：**这改动是不是当初要的东西**（它不知道 `/grill-me` 的计划）。两者配合用，不是二选一。
>
> **分层标准（0.3.0）**：常驻的入场券是双重测试 —— **触发点在模型盲区**（正要说"修好了"、批评刚到、同一个 bug 修第二刀：这些瞬间模型不会觉得自己需要被拦），**且内容是护栏而非教材**（Claude 已掌握工程知识本身，技能补的是行为约束，不是重讲一遍软件工程课）。TDD 和开工作区是工作方式的选择，时机该由你掌控 —— 官方文档也把"想控制时机的工作流"归给 `disable-model-invocation`。`implement` 不再跨层调用它们（模型调不到手动技能），改为内联各自的一句话护栏（接缝先约定、纵切、工作区先问再开、基线先绿），完整版留给手动的 `/tdd` 和 `/worktree`。
>
> **适用边界**：这套面向**交互式会话 + 强模型**。长时间无人值守的任务（夜跑代理、批量重构）没有人随时纠偏，superpowers 式的强制前置检查、全量 brainstorming 和细粒度计划在那种场景是安全网，不是税 —— 别拿这套去跑无人值守。

## 安装

**macOS / Linux**

```bash
git clone https://github.com/zhoukaichaoaa/lean-skills.git
cd lean-skills
./install.sh              # 覆盖前会逐个询问；-y 跳过询问
```

脚本是 POSIX `sh`，不依赖 bash 4（macOS 自带的是 bash 3.2）。如果提示 `Permission denied`，说明克隆时丢了可执行位，用 `sh install.sh` 或先 `chmod +x install.sh`。

**Windows**

```powershell
git clone https://github.com/zhoukaichaoaa/lean-skills.git
cd lean-skills
.\install.ps1             # 覆盖前会逐个询问；-Yes 跳过询问
```

两个脚本都把技能复制到 `~/.claude/skills/`，重启会话生效。装到别处：设 `CLAUDE_SKILLS_DIR` 环境变量。

**卸载 / 升级**：

```bash
./install.sh --uninstall      # Windows: .\install.ps1 -Uninstall
```

只移除本合集的 9 个技能，你自己创建的技能不动。跨版本升级时如果某个技能被改名或删除，普通覆盖不会清掉旧目录 —— 先 `--uninstall` 再装。

安装器在动手前用**写探针**确认目标不是源目录：往目标写一个标记文件，若它出现在仓库的 `skills/` 里就直接拒绝。这比比较路径字符串更可靠 —— 符号链接、Windows junction、链式链接、父目录是链接、大小写差异都骗不过它（v0.5.0 修复：此前 Windows 上一个指向仓库的 junction 能让 `-Uninstall` 静默删光源文件）。

也可以作为插件安装：

```
/plugin marketplace add zhoukaichaoaa/lean-skills
/plugin install lean-skills@lean-skills
```

插件模式下技能带命名空间：`/lean-skills:implement`。裸名 `/implement` 通常也能用——[除非同名的命令已经存在](https://code.claude.com/docs/en/skills#skill-locations)。本合集没有与内置技能重名的技能（`spec-review` 正是为此从 `code-review` 改名），所以两种写法都可以。

### 如果你已经装了 superpowers 插件

它带一个 SessionStart hook，每次会话把 `using-superpowers` 全文注入上下文，里面有一条"哪怕只有 1% 可能相关也必须调用技能"。这条规则是为对抗早期模型跳过流程写的，今天的边际收益很低，但 token 成本没降。

本合集与它冲突。二选一：

```
/plugin uninstall superpowers@superpowers-marketplace
```

插件的 cache 目录是托管的，改里面的 `hooks.json` 会在下次更新时被覆盖，**不要那样做**。想保留 superpowers 的技能又不要它的注入，在 `/plugin` 界面里禁用该插件，再手工挑需要的技能复制到 `~/.claude/skills/`。

装着 mattpocock/skills 插件的话没有 hook 冲突，命令名也不会真的撞车（插件技能带 `插件名:` 命名空间）。真正的代价是**语义重叠**：`tdd`、`implement` 等两边都有用途相近的 description，模型每轮都要在两套里选，上下文和选择面都变大。建议按需二选一。

## 用法

### 先分档

强制流程是这类东西最大的失败模式。

| 任务规模 | 走什么 |
|---|---|
| 意图明确、影响面清楚 | 不调任何技能。改完跑测试，把真实输出贴出来 |
| 一个模块、几个文件 | `/grill-me` → `/implement` |
| 新系统 / 跨模块重构 | `/grill-me` → `/worktree` → `/implement` → 完事后 `git worktree remove` |

常驻的 5 个不需要你操心 —— 它们会在该出现的时候自己出现（评审反馈到来时 `receiving-code-review` 自动接手；`git pull` 撞上冲突时 `resolving-merge-conflicts` 自动接手）。

**装完先做个冒烟测试**：新开一个会话，敲 `/`，**九个技能应当全部出现**。`disable-model-invocation` 只阻止模型自动调用，[不隐藏斜杠菜单](https://code.claude.com/docs/en/skills#control-who-invokes-a-skill)——想让某个技能从菜单消失，得另加 `user-invocable: false`。看不到就是没装上或没重启会话。

**不想要某一个**：`rm -rf ~/.claude/skills/<名字>` 即可，但下次 `./install.sh` 会把它装回来 —— 长期不要就从你的 fork 里删掉那个目录。

### `/implement` 内部做什么

```
读 /grill-me 写下的计划（没有且改动不小 → 先去 grill）
  → 隔离（大改动先问一句；分支按票命名 / .git/info/exclude / 基线先跑）
  → 开工前记下 BASE_SHA（原地修改也有明确的审查起点）
  → 按计划里约定的接缝纵切：一个失败测试 → 刚好通过的实现 → 重复
  → typecheck / 单文件测试跑着，最后跑全量
  → verification-before-completion：每个结论都带命令输出，计划里每条决策都有交代
  → spec-review（forked 子代理）：这改动是不是计划要的东西
  → 请你跑内置 /code-review：正确性、安全、清理
  → receiving-code-review：逐条核实评审发现再动手
  → 改完再验一遍：修 finding 会让上一步的证据失效
  → 交付：diff 摆出来，你点头才 commit
```

### 为什么计划是这套流程的枢纽

`/grill-me` 只留下"我们聊明白了"的感觉，会话一结束就蒸发。更要命的是**没有计划，`spec-review` 就无事可做** —— 它找 spec 的顺序是：调用者给的路径 → commit 里的 issue 号 → 计划文件 → `docs/` 下的 spec。本地开发前三项通常一个都没有，于是它只能报告"无 spec"然后停下（凭 diff 反推 spec 等于拿改动审自己）。而内置 `/code-review` 再强也回答不了"这是不是当初要的东西"——它没见过那场访谈。

书面计划一次接通三条轨道：

| 消费者 | 用计划的哪部分 |
|---|---|
| `implement` | Decisions 照着建，Seams 决定测在哪（第 6 步前重读一遍——长任务里它早被压缩掉了） |
| `verification-before-completion` | 逐条核对"每个决策是否有交代"——测试通过只证明代码能跑，不证明它是被要求的那个代码 |
| `spec-review` | 终于有 spec 可对；Out of scope 一节让范围蔓延现形 |

计划写在 **`$(git rev-parse --git-common-dir)/../.plans`** —— 这个表达式在主检出和 linked worktree 里都指向主检出。直接写 `.plans/` 会踩一个坑：未跟踪文件**不会**进入 linked worktree，而 exclude 规则会，于是"先 `/worktree` 再 `/implement`"的推荐流程里，计划在 worktree 内找不到，Spec 轴又退回空转。三处（`grill-me` 写、`implement` 读、`spec-review` 找）用的是同一条表达式，改位置要三处一起改。非 git 目录下退化为当前目录的 `.plans/`。

不自动提交 —— 和本合集其他地方一样，提交是你的决定。用完记得 `git worktree remove`：worktree 和计划都被 exclude，**永远不出现在 `git status` 里**，不会有人提醒你它们在堆积。

中途发现是"坏了"而不是"没建"，切到 `diagnosing-bugs`。

### 可选：`CONTEXT.md` 与 ADR

`tdd` 和 `diagnosing-bugs` 里有一句"如果仓库里有 `CONTEXT.md` 就先读它，并尊重相关的 ADR"。这两样本合集不产出，**没有也不影响使用** —— 两处引用都是条件式的。

它们指的是：

- **`CONTEXT.md`** —— 项目的领域词汇表。写清楚这个项目里"订单""租户""结算"各自到底指什么，让测试命名和接口用词都落在同一套语言上。手写一份就行。
- **ADR**（Architecture Decision Record）—— 记录"为什么这么设计"的短文档，通常放在 `docs/adr/`。防止后来者（包括模型）把有意为之的设计当成疏漏改掉。

想要自动生成这两样，用 mattpocock 的 [`grill-with-docs`](https://github.com/mattpocock/skills/tree/main/skills/engineering/grill-with-docs)，它是一场访谈，产出 `CONTEXT.md` 和 ADR。本合集没有收录它，因为它是一次性投入，不值得占常驻位置。

## 维护

改技能之前先读 [DOCTRINE.md](DOCTRINE.md) —— 技能设计的一套词汇和原则（源自 mattpocock 的 `writing-great-skills`）。核心几条：

- **正向表述。** "别想大象"会让大象更容易被想起来。说要做什么，而不是禁止什么。
- **完成判据要可检查。** "产出一份变更清单"是模糊的，"每个改动过的模型都被覆盖到"是可检查的。
- **删空转句。** 一句话如果模型默认就会照做，它就在白占 token。
- **一处真相。** 同一个意思出现在两个地方，就是维护成本加倍、且在信息层级上被虚高。

新增技能之前，先用收录标准的三个问题过一遍。加进来容易，删掉难 —— 这就是两个上游仓库都在积累"沉积层"的原因。

版本历史见 [CHANGELOG.md](CHANGELOG.md)。

## 归属

本合集是衍生作品，上游两个仓库都是 MIT。逐文件的来源和改动记录见 [NOTICE.md](NOTICE.md)。

- [mattpocock/skills](https://github.com/mattpocock/skills) — MIT © 2026 Matt Pocock
- [obra/superpowers](https://github.com/obra/superpowers) — MIT © 2025 Jesse Vincent

## License

MIT
