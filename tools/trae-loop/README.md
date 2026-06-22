# trae-loop

Claude Code Island 的编排器。把"从需求到可运行产物"的开发流程拆成 4 个阶段，每个阶段输出一份 Markdown 执行文档；由"桥接人"把该文档粘贴给 Trae IDE Agent 执行，然后回到 trae-loop 确认结果，再推进到下一阶段。

## 核心思想

- **拆分阶段**：把大型任务拆成 4 个独立且可回归的阶段，降低一次性交付的风险。
- **阶段产物 = Markdown**：每个阶段输出一份结构化的执行文档，既是给 Agent 的指令，也是给桥接人的审阅材料。
- **人工确认 y / n / redo**：在阶段边界让桥接人做 yes/no/redo 决策，确保推进是可控的。
- **可复现**：`state.json` 持久化当前进度，重跑时可以从任意阶段继续，甚至手动跳转阶段。

# 目录结构

```
trae-loop/
├── trae-loop.py                 # 主入口：编排 4 个阶段，处理 y/n/redo 交互
├── lib/                         # 核心模块
│   ├── state_manager.py         # state.json 读写、版本号、字段校验
│   ├── phase_checker.py         # 每个阶段的"是否可进入下一阶段"的检查逻辑
│   ├── prompt_engine.py         # 基于 execution-templates/ 渲染执行文档
│   ├── trae_bridge.py           # 与 Trae IDE Agent 的桥接层（真实模式下调用外部工具）
│   └── environment_checker.py   # 环境预检：Python 版本、目录结构、必需文件
├── execution-templates/         # 4 个阶段模板
│   ├── 01-requirements-architecture.md
│   ├── 02-macos-island.md
│   ├── 03-ios-companion.md
│   └── 04-integration-verification.md
├── execution/                   # 运行时产物（已在 .gitignore 中）
├── state.json                   # 运行时持久化状态（已在 .gitignore 中）
├── state-schema.json            # state.json 的 JSON Schema
└── tests/                       # 单元测试
    ├── test_state_manager.py
    ├── test_phase_checker.py
    ├── test_prompt_engine.py
    ├── test_trae_bridge.py
    ├── test_environment_checker.py
    ├── test_templates.py
    └── test_mock_loop.py
```

# 快速开始

## 1. 全流程 mock（不依赖 Trae）

适合本地自验。`--mock` 会跳过真实的 Agent 调用，直接让你确认产物是否合理。

```bash
cd trae-loop
rm -f state.json
python3 trae-loop.py --mock --input "done\ny\ndone\ny\ndone\ny\ndone\ny"
```

每个阶段结束后，程序会在终端打印 `y / n / redo` 提示。在 mock 模式下，如果通过 `--input` 传入了预设序列，程序会按该序列自动应答。

## 2. 真实运行（需要 Trae IDE Agent）

```bash
cd trae-loop
python3 trae-loop.py
```

流程：
1. trae-loop 渲染当前阶段的执行文档，写入 `execution/*.md`
2. 桥接人打开该文件，把内容粘贴给 Trae IDE Agent 执行
3. Agent 完成后，桥接人回到终端输入 `y / n / redo`
4. `y` 推进到下一阶段；`n` 退出留档；`redo` 重新渲染当前阶段

## 3. 只从某阶段开始

`--phase` 参数可直接跳到指定阶段：

```bash
python3 trae-loop.py --phase macos-island
```

合法的阶段名（大小写不敏感）：
- `requirements-architecture`
- `macos-island`
- `ios-companion`
- `integration-verification`

# 交互方式 y / n / redo

在每个阶段产物输出后，程序会提示：

```
Phase <name> attempt <N> rendered to execution/<file>.md
请由桥接人把该文档交给 Trae IDE Agent 执行，完成后回到这里：
  y    : 确认通过，推进到下一阶段
  n    : 拒绝，保留当前阶段状态并退出（人工检查后可重新 `python3 trae-loop.py` 从当前阶段继续）
  redo : 重试当前阶段，重新渲染执行文档，attempt 计数 +1
>
```

交互规则：

- **`y`**：检查当前阶段是否满足进入下一阶段的条件（由 `phase_checker` 负责）。通过则 `currentPhase` 推进到下一阶段，`currentAttempt` 重置为 1。
- **`n`**：程序把 `status` 标记为 `blocked-by-human` 并退出；历史记录写入 `history`。下一次运行仍会停在当前阶段，方便人工审阅后继续。
- **`redo`**：`currentAttempt` 加 1，重新渲染当前阶段执行文档。若 `currentAttempt > maxAttempts` 则以错误退出，避免死循环。

# state.json 字段说明

`state.json` 是 trae-loop 唯一的持久化状态源，字段如下：

| 字段            | 类型         | 说明 |
| --------------- | ------------ | ---- |
| `projectName`   | string       | 项目标识，固定为 `claude-code-island` |
| `version`       | string       | 当前 state schema 版本，用于向前兼容 |
| `currentPhase`  | string       | 当前正在处理的阶段（四选一） |
| `status`        | string       | `running` / `blocked-by-human` / `failed` / `done` |
| `history`       | array of objects | 每次阶段推进或决策都会被写入历史，含 phase、action、attempt、time |
| `currentAttempt`| integer      | 当前阶段已经尝试了几次（每次 `redo` +1） |
| `maxAttempts`   | integer      | 每个阶段最多重试次数，默认 5 |
| `artifacts`     | object       | 每个阶段产物的文件路径与生成时间 |
| `errors`        | array of strings | 历史错误信息栈 |
| `startedAt`     | string (ISO) | 首次创建 state 的时间戳 |
| `updatedAt`     | string (ISO) | 最近一次修改 state 的时间戳 |

你可以手动编辑 `state.json` 来改变 `currentPhase`，这是一个低级别逃生舱。编辑后建议再次运行 `python3 trae-loop.py` 让程序做一次自检。

# 测试

所有测试都是纯标准库，无需安装任何第三方依赖。

```bash
cd trae-loop

python3 -m tests.test_state_manager
python3 -m tests.test_phase_checker
python3 -m tests.test_prompt_engine
python3 -m tests.test_trae_bridge
python3 -m tests.test_environment_checker
python3 -m tests.test_templates
python3 -m tests.test_mock_loop
```

`tests.test_mock_loop` 会完整跑一遍 4 个阶段的 mock 流程，检查 `execution/` 产物与 `state.json` 演进是否符合预期。

# 注意

- **零第三方依赖**：trae-loop 只使用 Python 标准库，无需 `pip install`。
- **.gitignore**：`execution/*.md` 与 `state.json` 已被忽略，只保留模板与源代码。
- **手动跳转阶段**：直接编辑 `state.json` 中的 `currentPhase` 字段即可；程序启动时会读取该字段。
- **Phase D checker 的宽松要求**：项目自检会确保 README.md 至少包含 3 个以 `#` 开头的标题行，作为"文档可读性基线"的一个最小约束。
