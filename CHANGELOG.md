# Changelog

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
