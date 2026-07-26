# Changelog

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

## 0.3.1 — 2026-07-26（`81c27ae`）

- code-review：子代理改收字面 SHA（`$BASE` 不跨 shell）；merge-base 失败显式停下而非静默降级；无关 WIP 可退回 committed-only；worktree 的 .gitignore 是否提交交还用户

## 0.3.0 — 2026-07-26（`f53c68a`）

- 常驻 7 → 4：入场券改为"盲区触发 + 护栏而非教材"双重测试；tdd / worktree / resolving-merge-conflicts 降手动
- 修四缺陷：worktree `$BRANCH` 未定义；code-review 审不到 WIP；`--abort` 绝对禁令放宽；implement 无条件 commit 改为经授权
- implement 不再跨层调用手动技能，改为内联一句话护栏
- README 写明适用边界：交互式会话 + 强模型；无人值守长任务适合 superpowers 式流程

## 0.2.0 — 2026-07-26（`8d5957f`）

- 修复编排不可达：implement 调用的 worktree / receiving-code-review 当时是手动技能，模型调不到——按官方 `disable-model-invocation` 语义翻为常驻（该决定在 0.3.0 被更好的内联方案取代）
- CI 三平台矩阵上线；NOTICE 词数改为实测值

## 0.1.0 — 2026-07-26（`e8b9a66`）

- 首发：9 技能（5 常驻 / 4 手动），双安装脚本，DOCTRINE / NOTICE / 双上游 MIT 归属

---

**发布清单**：改 manifests 版本号 → 更新本文件 → 本地全量验证 + 自审 → commit & push → CI 绿 → `git tag vX.Y.Z && git push --tags` → `gh release create` → 核对 GitHub description → `claude plugin validate --strict .`
