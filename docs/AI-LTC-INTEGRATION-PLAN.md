# AI-LTC 框架集成计划

将 AI-LTC (AI-LongTimeCoding) 框架集成到 OML 项目中，辅助长期 AI 协作和项目推进。

---

## 一、AI-LTC 框架概述

### 1.1 什么是 AI-LTC

AI-LTC = **AI-LongTimeCoding(plan)**

一套面向长期 AI 辅助开发的可复用协作框架，把分阶段的 GPT/Qwen 协作方式沉淀成可复制、改造、持续演化的工作骨架。

### 1.2 核心价值

- **GPT 负责高成本的架构设计**，以及按需介入的优化/审计
- **Qwen 负责默认的日常评估、监督、执行与持续推进**
- **交接、升级、relay、文档自进化等规则都被显式写出来**
- 减少跨会话和跨模型时的上下文重建成本

### 1.3 四层架构

```
Layer 0: Shared Contract
  -> 公共规则、停止信号、状态字段、范围护栏

Layer 1: Role Prompts
  -> GPT 架构师/优化师，Qwen init/执行/监督

Layer 2: Skeleton And Relay Surface
  -> 可复用 docs/、.ai/、模板与示例结构

Layer 3: Runtime Working State
  -> active lane 文档、handoff、escalation、init 状态
```

### 1.4 A-B-O 生命周期

| 角色 | 模型 | 职责 |
|------|------|------|
| **Architect** | GPT-5.4 | 起步架构、骨架与交接 |
| **Builder** | Qwen 3.5 Plus | 日常执行、监督与 bounded iteration |
| **Optimizer** | GPT-5.4 | 专项审计、重构或硬阻塞时回场 |

---

## 二、AI-LTC 状态流

### 2.1 核心流程

```text
init
  -> handoff-ready
  -> execution
  -> review-gate or escalation
  -> optimizer-intervention
  -> optimizer-return
  -> execution
  -> checkpoint / closeout
```

### 2.2 状态详解

| 状态 | 目的 | 主要操作者 | 产物 |
|------|------|-----------|------|
| **init** | 分类项目状态，解析 AI-LTC 源模式 | Qwen | `.ai/system/ai-ltc-config.json` |
| **handoff-ready** | 架构师到构建师的交接 | GPT | `00_HANDOFF.md` |
| **execution** | 正常交付，bounded 实现 | Qwen | `.ai/active-lane/*` |
| **review-gate** | 有意义的证据后的暂停 | Qwen | 下一行动明确 |
| **escalation** | 架构级阻塞打包 | Qwen 准备 | `ESCALATION_REQUEST.md` |
| **optimizer-intervention** | 窄高价值问题解决 | GPT | 窄重设计/审计 |
| **optimizer-return** | 控制权交还 Qwen | GPT 写，Qwen 执行 | 更新 lane 文档 |
| **checkpoint-closeout** | 批次/里程碑/lane 结束 | Qwen | 状态保存 |

---

## 三、OML 项目集成方案

### 3.1 目录结构集成

```
oh-my-litecode/
├── .ai/                           # AI-LTC 运行时状态
│   ├── active-lane/               # 当前活动 lane
│   │   ├── ai-handoff.md          # AI 交接文档
│   │   ├── current-status.md      # 当前状态
│   │   └── roadmap.md             # 路线图
│   └── system/                    # 系统配置
│       ├── ai-ltc-config.json     # AI-LTC 配置
│       └── init-status.md         # Init 状态
│
├── docs/                          # 设计文档 (Static 层)
│   ├── AI-LTC-INTEGRATION-PLAN.md # 本集成计划
│   ├── DESIGN-DOCUMENTS-INDEX.md # 设计文档索引
│   ├── OML-QWEN-DEEP-DESIGN.md   # Qwen 深度设计
│   ├── TYPESCRIPT-REFACTOR-PLAN.md # TS 重构计划
│   └── ...
│
├── prompts/                       # AI-LTC Prompt 库
│   ├── shared-repo-contract.prompt.md
│   ├── gpt-bootstrap-architect.prompt.md
│   ├── gpt-optimizer-auditor.prompt.md
│   ├── qwen-init-routing.prompt.md
│   ├── qwen-generalist-autopilot.prompt.md
│   └── qwen-supervisory-generalist.prompt.md
│
├── templates/                     # AI-LTC 模板
│   ├── 00_HANDOFF.template.md
│   ├── ESCALATION_REQUEST.template.md
│   ├── AI-LTC-INIT-QUESTIONNAIRE.template.md
│   └── human-addendum.template.md
│
└── examples/                      # AI-LTC 示例
    └── collaboration-system/
        └── project-template/
```

### 3.2 三层变更分类

| 变更类别 | 说明 | OML 示例 |
|----------|------|----------|
| **Static** | 稳定的框架规则 | `docs/` 设计文档，模板 |
| **Dynamic** | 实时项目状态 | `.ai/active-lane/*` |
| **Self-Evolving** | 从实践中进化 | `prompts/`, `templates/` |

---

## 四、集成实施步骤

### 阶段 1: 框架部署 (1 天) 🔴

**目标**: 部署 AI-LTC 框架基础设施

- [ ] 创建 `.ai/` 目录结构
- [ ] 创建 `prompts/` 目录
- [ ] 创建 `templates/` 目录
- [ ] 复制 AI-LTC 核心 prompt
- [ ] 创建 `ai-ltc-config.json`

**交付物**:
- `.ai/system/ai-ltc-config.json`
- `.ai/system/init-status.md`
- `prompts/` 基础 prompt 库

### 阶段 2: Init 状态建立 (1 天) 🔴

**目标**: 使用 `qwen-init-routing.prompt.md` 建立 init 状态

- [ ] 运行 `qwen-init-routing.prompt.md`
- [ ] 分类项目状态 (TypeScript 重构期)
- [ ] 解析 AI-LTC 源模式 (本地)
- [ ] 建立 resolver 配置
- [ ] 创建初始 handoff 文档

**交付物**:
- `.ai/system/init-status.md`
- `00_HANDOFF.md` (初始版本)
- `.ai/active-lane/current-status.md`

### 阶段 3: TypeScript 重构 Lane 启动 (2 周) 🟡

**目标**: 在 execution 状态启动 TypeScript 重构

- [ ] 定义初始 lane (TypeScript Core 重构)
- [ ] 设置 lane 文档
- [ ] 使用 `qwen-generalist-autopilot.prompt.md` 进入执行
- [ ] 按 bounded iteration 推进

**交付物**:
- `.ai/active-lane/roadmap.md`
- `.ai/active-lane/ai-handoff.md`
- 每周 checkpoint 文档

### 阶段 4: 监督与审查 (持续) 🟡

**目标**: 使用 `qwen-supervisory-generalist.prompt.md` 进行监督

- [ ] 每周监督审查
- [ ] 更新 lane 状态
- [ ] 收集 proof evidence
- [ ] 通过 review-gate 决策

**交付物**:
- 每周审查报告
- `.ai/active-lane/current-status.md` 更新
- Review-gate 决策记录

### 阶段 5: 升级与优化 (按需) 🟢

**目标**: 遇到架构级阻塞时使用 escalation

- [ ] 识别架构级阻塞
- [ ] 创建 `ESCALATION_REQUEST.md`
- [ ] GPT optimizer 介入
- [ ] 记录 optimizer-return

**交付物**:
- `ESCALATION_REQUEST.md` (按需)
- Optimizer 审计报告
- 更新的设计文档

---

## 五、AI-LTC 配置

### 5.1 ai-ltc-config.json

```json
{
  "version": "1.0.0",
  "projectName": "oh-my-litecode",
  "projectState": "typescript-refactor",
  "sourceMode": "local",
  "localPath": "/home/miao/develop/AI-LTC",
  "resolver": {
    "primaryModel": "qwen-3.5-plus",
    "architectModel": "gpt-5.4",
    "optimizerModel": "gpt-5.4",
    "language": "zh-CN",
    "outputFormat": "markdown"
  },
  "activeLane": {
    "name": "typescript-core-refactor",
    "status": "init",
    "owner": "qwen",
    "nextAction": "run qwen-init-routing",
    "blockers": []
  },
  "guardrails": {
    "boundedPassLimit": 3,
    "escalationThreshold": "architecture-deadlock",
    "stopPhrases": ["ESCALATION_REQUIRED", "HANDOFF_READY", "CHECKPOINT_REACHED"]
  }
}
```

### 5.2 init-status.md

```markdown
# Init Status

## Project Classification

- **State**: TypeScript 重构期
- **AI-LTC Source**: Local (`/home/miao/develop/AI-LTC`)
- **GPT Bootstrap Required**: No (已有完整设计文档)
- **Next Primary Operator**: Qwen 3.5 Plus

## Current Lane

- **Name**: typescript-core-refactor
- **Phase**: init
- **Owner**: Qwen

## Next Actions

1. 创建 `.ai/` 目录结构
2. 部署 AI-LTC prompts 和 templates
3. 进入 execution 状态
```

---

## 六、Prompt 库

### 6.1 核心 Prompt

| Prompt | 用途 | 阶段 |
|--------|------|------|
| `shared-repo-contract.prompt.md` | 公共规则 | 所有 |
| `qwen-init-routing.prompt.md` | Init 分流 | init |
| `qwen-generalist-autopilot.prompt.md` | 日常执行 | execution |
| `qwen-supervisory-generalist.prompt.md` | 监督审查 | review-gate |
| `gpt-bootstrap-architect.prompt.md` | 架构搭建 | handoff-ready |
| `gpt-optimizer-auditor.prompt.md` | 优化审计 | optimizer-intervention |

### 6.2 模板库

| 模板 | 用途 |
|------|------|
| `00_HANDOFF.template.md` | AI 交接 |
| `ESCALATION_REQUEST.template.md` | 升级请求 |
| `AI-LTC-INIT-QUESTIONNAIRE.template.md` | Init 问卷 |
| `human-addendum.template.md` | 人类补充 |

---

## 七、与现有设计文档集成

### 7.1 文档映射

| OML 文档 | AI-LTC 层 | 变更类别 |
|----------|----------|----------|
| `TYPESCRIPT-REFACTOR-PLAN.md` | Layer 2 | Self-Evolving |
| `OML-QWEN-DEEP-DESIGN.md` | Layer 2 | Static |
| `DESIGN-DOCUMENTS-INDEX.md` | Layer 2 | Static |
| `.ai/active-lane/*` | Layer 3 | Dynamic |

### 7.2 状态流集成

```
OML TypeScript 重构计划
    ↓
AI-LTC State Flow
    ↓
init -> execution -> review-gate -> checkpoint-closeout
    ↓
每周推进 TypeScript 重构
```

---

## 八、Guardrails 和规则

### 8.1 停止短语

| 短语 | 含义 | 下一状态 |
|------|------|----------|
| `ESCALATION_REQUIRED` | 架构级阻塞 | escalation |
| `HANDOFF_READY` | 交接准备就绪 | handoff-ready |
| `CHECKPOINT_REACHED` | 检查点到达 | checkpoint-closeout |
| `REVIEW_GATE` | 审查门到达 | review-gate |
| `OPTIMIZER_RETURN` | 优化师返回 | optimizer-return |

### 8.2 状态字段

```markdown
## Status

- **State**: execution
- **Lane**: typescript-core-refactor
- **Owner**: Qwen 3.5 Plus
- **Next Action**: 实现 Session 模块
- **Blockers**: 无
- **Bounded Pass**: 1/3
```

### 8.3 范围护栏

- 不跳过 `init` 当 resolver 状态不明确
- 不跳过 `handoff-ready` 当 GPT 搭建了骨架
- 不因 GPT 更强而从 `execution` 调用 GPT
- 总是在 optimizer 干预前创建 `ESCALATION_REQUEST.md`
- 总是在 optimizer 干预后返回 Qwen

---

## 九、实施时间表

| 阶段 | 时间 | 目标 | 状态 |
|------|------|------|------|
| 阶段 1: 框架部署 | 1 天 | 基础设施 | 📋 待开始 |
| 阶段 2: Init 状态 | 1 天 | Init 建立 | 📋 待开始 |
| 阶段 3: TS 重构 | 2 周 | execution | 📋 待开始 |
| 阶段 4: 监督审查 | 持续 | review-gate | 📋 待开始 |
| 阶段 5: 升级优化 | 按需 | escalation | 📋 待开始 |

---

## 十、参考资源

### AI-LTC 框架
- `/home/miao/develop/AI-LTC/README.zh.md`
- `/home/miao/develop/AI-LTC/ARCHITECTURE-LAYERS.md`
- `/home/miao/develop/AI-LTC/STATE-FLOWS.md`
- `/home/miao/develop/AI-LTC/INIT-RECIPES.md`
- `/home/miao/develop/AI-LTC/USE-CASES.md`

### OML 设计文档
- `TYPESCRIPT-REFACTOR-PLAN.md`
- `OML-QWEN-DEEP-DESIGN.md`
- `DESIGN-DOCUMENTS-INDEX.md`

---

**文档创建时间**: 2026 年 3 月 26 日
**AI-LTC 版本**: v1
**OML 版本**: 0.2.0
