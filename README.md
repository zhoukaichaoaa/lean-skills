# lean-skills

> 9 个技能。5 个常驻，4 个手动。没有强制条款，没有启动注入。

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
| `diagnosing-bugs` | 不建复现回路，直接猜 bug 原因 | mattpocock，微调 |
| `tdd` | 先写实现再补测试；测到实现细节上 | mattpocock，原文 |
| `code-review` | 自己写完自己觉得没问题 | mattpocock，去依赖 |
| `resolving-merge-conflicts` | 冲突了就 `--abort` 或随便选一边 | mattpocock，原文 |

**手动（打斜杠才加载，零上下文成本）**

| 技能 | 用途 | 来源 |
|---|---|---|
| `grill-me` | 动手前把需求追问到收敛 | mattpocock，合并 |
| `implement` | 编排：隔离 → TDD → 验证 → 评审 | mattpocock，扩写 |
| `worktree` | 建隔离工作区，保护当前分支 | superpowers，精简 |
| `receiving-code-review` | 治"评审说啥都点头照做" | superpowers，重写 |

## 安装

```bash
git clone https://github.com/zhoukaichaoaa/lean-skills.git
cd lean-skills
./install.sh          # Windows: .\install.ps1
```

技能会被复制到 `~/.claude/skills/`，重启会话生效。

也可以作为插件安装：

```
/plugin marketplace add zhoukaichaoaa/lean-skills
/plugin install lean-skills@lean-skills
```

### 如果你已经装了 superpowers 插件

它带一个 SessionStart hook，每次会话把 `using-superpowers` 全文注入上下文，里面有一条"哪怕只有 1% 可能相关也必须调用技能"。这条规则是为对抗早期模型跳过流程写的，今天的边际收益很低，但 token 成本没降。

本合集与它冲突。二选一：

```
/plugin uninstall superpowers@superpowers-marketplace
```

或保留插件，把 `~/.claude/plugins/cache/superpowers-marketplace/superpowers/*/hooks/hooks.json` 改成 `{"hooks":{}}`（注意插件更新会覆盖）。

## 用法

### 先分档

强制流程是这类东西最大的失败模式。

| 任务规模 | 走什么 |
|---|---|
| 意图明确、影响面清楚 | 不调任何技能。改完跑测试，把真实输出贴出来 |
| 一个模块、几个文件 | `/grill-me` → `/implement` |
| 新系统 / 跨模块重构 | `/grill-me` → `/worktree` → `/implement` → `/receiving-code-review` |

常驻的 5 个不需要你操心 —— 它们会在该出现的时候自己出现。

### `/implement` 内部做什么

```
worktree（可选）
  → 约定测试接缝 → tdd 逐个纵切
  → typecheck / 单文件测试跑着，最后跑全量
  → verification-before-completion：每个结论都带命令输出
  → code-review：Standards 轴 + Spec 轴并行
  → commit
```

中途发现是"坏了"而不是"没建"，切到 `diagnosing-bugs`。

## 维护

改技能之前先读 [DOCTRINE.md](DOCTRINE.md) —— 技能设计的一套词汇和原则（源自 mattpocock 的 `writing-great-skills`）。核心几条：

- **正向表述。** "别想大象"会让大象更容易被想起来。说要做什么，而不是禁止什么。
- **完成判据要可检查。** "产出一份变更清单"是模糊的，"每个改动过的模型都被覆盖到"是可检查的。
- **删空转句。** 一句话如果模型默认就会照做，它就在白占 token。
- **一处真相。** 同一个意思出现在两个地方，就是维护成本加倍、且在信息层级上被虚高。

新增技能之前，先用收录标准的三个问题过一遍。加进来容易，删掉难 —— 这就是两个上游仓库都在积累"沉积层"的原因。

## 归属

本合集是衍生作品，上游两个仓库都是 MIT。逐文件的来源和改动记录见 [NOTICE.md](NOTICE.md)。

- [mattpocock/skills](https://github.com/mattpocock/skills) — MIT © 2026 Matt Pocock
- [obra/superpowers](https://github.com/obra/superpowers) — MIT © 2025 Jesse Vincent

## License

MIT
