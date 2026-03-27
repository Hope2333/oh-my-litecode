# Archive 清单

**最后更新**: 2026-03-23  
**状态**: 📦 历史存档（只读）

---

## 📁 Archive 内容

本目录包含 OML 项目的历史版本存档，用于：
- 历史参考
- 迁移指南
- 教育意义
- 紧急回滚

---

## 📦 存档列表

### legacy-qwenx/ (实验室版)

| 属性 | 值 |
|------|-----|
| **状态** | ❌ 已废弃 |
| **存档日期** | 2026-03-23 |
| **代码量** | 823 行 Bash |
| **存储占用** | 55 KB (压缩后 <20 KB) |
| **推荐** | 不推荐新开发，请使用 0.1.0 版本 |

#### 存档内容

```
legacy-qwenx/
├── qwenx.legacy.sh        # 实验室版 qwenx 脚本
├── AGENTS.md              # Agent 配置
├── COMPATIBILITY.md       # 兼容性文档
├── compat.layer.json      # 兼容层配置
├── example.settings.json  # 配置示例
├── README.md              # 存档说明
└── migration-guide.md     # 迁移指南
```

#### 废弃原因

1. **安全问题**: API 密钥硬编码
   ```bash
   # ❌ 错误做法（实验室版）
   export QWEN_API_KEY="sk-..ZF7"
   
   # ✅ 正确做法（OML 版）
   export QWEN_API_KEY="${QWEN_API_KEY:-}"
   ```

2. **功能缺失**:
   - ❌ 无 Session 管理系统
   - ❌ 无 Hooks 自动化引擎
   - ❌ 无 Worker 池并行执行
   - ❌ 无完整插件系统

3. **维护困难**:
   - ❌ 无自动更新
   - ❌ 无健康检查
   - ❌ 文档不完整

#### 使用场景

| 场景 | 推荐度 | 说明 |
|------|--------|------|
| **历史研究** | ✅ 推荐 | 了解项目演进 |
| **迁移参考** | ✅ 推荐 | 从旧版迁移到新版 |
| **教育用途** | ✅ 推荐 | 学习安全最佳实践 |
| **新开发** | ❌ 不推荐 | 请使用 0.1.0 版本 |
| **生产环境** | ❌ 不推荐 | 存在安全隐患 |

#### 迁移指南

**从实验室版迁移到 OML 0.1.0**:

```bash
# 1. 备份现有配置
cp -r ~/.local/home/qwenx/.qwen ~/.local/home/qwenx.backup

# 2. 安装 OML
git clone https://github.com/Hope2333/oh-my-litecode.git
cd oh-my-litecode

# 3. 运行迁移脚本
bash scripts/update-qwenx.sh

# 4. 验证迁移
qwenx --oml-version
qwenx --oml-help
```

**详细指南**: [migration-guide.md](legacy-qwenx/migration-guide.md)

---

## 🔗 相关文档

| 文档 | 说明 |
|------|------|
| [项目历史](PROJECT-HISTORY-AND-STATUS.md) | 完整项目演进历史 |
| [版本标签](TAGS.md) | 0.1.0-bash 和 0.1.0 版本说明 |
| [迁移指南](legacy-qwenx/migration-guide.md) | 详细迁移步骤 |
| [Archive 评估](ARCHIVE-EVALUATION.md) | Archive 去留评估报告 |

---

## ❓ 常见问题

### Q: 为什么保留已废弃的代码？

**A**: 
- 历史参考价值（展示项目演进）
- 迁移指南需要（帮助用户从旧版迁移）
- 教育意义（反面教材，学习安全最佳实践）
- 存储成本极低（<20 KB 压缩后）

### Q: 我可以使用实验室版吗？

**A**: 
- **学习/研究**: ✅ 可以
- **新开发**: ❌ 不推荐，请使用 0.1.0 版本
- **生产环境**: ❌ 不推荐，存在安全隐患

### Q: 如何回滚到实验室版？

**A**: 
```bash
# 从 Archive 恢复
cp archive/legacy-qwenx/qwenx.legacy.sh /usr/bin/qwenx
chmod +x /usr/bin/qwenx

# 验证
qwenx --help
```

**注意**: 不推荐回滚，除非有特殊需求。

### Q: Archive 会占用多少空间？

**A**: 
- **未压缩**: 55 KB
- **Git 压缩后**: <20 KB
- **占比**: <0.6% 总仓库大小

---

## 📊 版本对比

| 特征 | 实验室版 | OML 0.1.0-bash | OML 0.1.0 |
|------|---------|--------------|----------|
| **语言** | 100% Bash | 100% Bash | TS + Py + Bash |
| **代码量** | 823 行 | ~26,000 行 | ~40,000 行 |
| **Session 管理** | ❌ | ✅ | ✅ (TS) |
| **Hooks 系统** | ❌ | ✅ | ✅ (Py) |
| **Worker 池** | ❌ | ✅ | ✅ (TS) |
| **插件数量** | 0 | 10+ | 10+ |
| **测试覆盖** | 0% | 100% | 100% |
| **API 密钥** | ⚠️ 硬编码 | ✅ 环境变量 | ✅ 环境变量 |
| **推荐** | ❌ | ⚠️ 保留 | ✅ 推荐 |

---

## 🎯 推荐版本

| 需求 | 推荐版本 | 理由 |
|------|---------|------|
| **新开发** | 0.1.0 | TypeScript/Python 混合架构 |
| **学习 Bash** | 0.1.0-bash | 完整 Bash 实现 |
| **历史研究** | Archive | 项目起源记录 |
| **生产环境** | 0.1.0 | 类型安全、易维护 |

---

## 📦 获取版本

### 当前版本 (推荐)

```bash
git clone --branch 0.1.0 https://github.com/Hope2333/oh-my-litecode.git
```

### Bash 版 (保留)

```bash
git clone --branch 0.1.0-bash https://github.com/Hope2333/oh-my-litecode.git
```

### 实验室版 (不推荐)

```bash
# 方式 1: 使用 Archive
cp archive/legacy-qwenx/qwenx.legacy.sh /usr/bin/qwenx

# 方式 2: 检出旧提交
git checkout 5b80f75
```

---

**维护者**: OML Team  
**最后更新**: 2026-03-23  
**许可**: MIT License
