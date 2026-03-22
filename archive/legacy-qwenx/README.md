# 实验室版 qwenx 存档

**存档日期**: 2026-03-23  
**版本**: 实验室版 (Legacy)  
**状态**: ❌ 已废弃 - 请迁移到 OML 版

---

## 📋 概述

此目录包含实验室版 qwenx 的完整备份，用于：
- 历史参考
- 配置迁移
- 功能对比
- 紧急回滚

---

## ⚠️ 重要提示

**实验室版已废弃，原因：**

1. **功能缺失**
   - ❌ 无 Session 管理系统
   - ❌ 无 Hooks 自动化引擎
   - ❌ 无 Worker 池并行执行
   - ❌ 无完整插件系统

2. **安全问题**
   - ⚠️ API 密钥硬编码
   - ⚠️ 无安全审计机制
   - ⚠️ 配置管理不规范

3. **维护困难**
   - ❌ 无自动更新
   - ❌ 无健康检查
   - ❌ 文档不完整

---

## 📁 存档内容

```
archive/legacy-qwenx/
├── README.md                      # 本说明文档
├── qwenx.legacy.sh                # 实验室版 qwenx 脚本
├── AGENTS.md                      # Agent 配置
├── COMPATIBILITY.md               # 兼容性文档
├── compat.layer.json              # 兼容层配置
├── example.settings.json          # 配置示例
└── migration-guide.md             # 迁移指南
```

---

## 🔄 迁移到 OML 版

### 快速迁移

```bash
# 1. 备份现有配置
cp -r ~/.local/home/qwenx/.qwen ~/.local/home/qwenx/.qwen.backup

# 2. 运行迁移脚本
bash ~/develop/oh-my-litecode/scripts/update-qwenx.sh

# 3. 验证迁移
qwenx --oml-version
qwenx --oml-help
```

### 配置迁移

```bash
# 迁移 Context7 密钥
cp ~/.local/home/qwenx/.qwenx/secrets/context7.keys \
   ~/.local/home/qwenx/.qwenx/secrets/context7.keys.backup

# 迁移自定义配置
# 注意：不要直接覆盖，需要手动合并配置
```

---

## 📊 版本对比

| 特性 | 实验室版 | OML 版 |
|------|---------|-------|
| **代码行数** | ~800 | ~25,000+ |
| **插件数量** | 0 | 10+ |
| **测试覆盖** | 0% | 100% (292 测试) |
| **文档完整度** | 30% | 100% |
| **安全审计** | ❌ | ✅ |
| **Session 管理** | ❌ | ✅ |
| **Hooks 系统** | ❌ | ✅ |
| **Worker 池** | ❌ | ✅ |

---

## 🔙 回滚指南

如需回滚到实验室版（不推荐）：

```bash
# 1. 停止 OML 服务
pkill -f "oml" || true

# 2. 恢复旧版命令
sudo cp archive/legacy-qwenx/qwenx.legacy.sh /usr/bin/qwenx
chmod +x /usr/bin/qwenx

# 3. 恢复配置
cp -r ~/.local/home/qwenx/.qwen.backup ~/.local/home/qwenx/.qwen

# 4. 验证回滚
qwenx --help
```

**注意**: 回滚后将失去所有 OML 新功能！

---

## 📚 相关文档

- [更新指南](../docs/UPDATE-QWENX-GUIDE.md)
- [配置指南](../docs/QWENX-CONFIG-GUIDE.md)
- [Arch Linux 部署](../docs/ARCH-QWENX-REDEPLOY-PROMPT.md)

---

## ⏰ 时间线

| 日期 | 事件 |
|------|------|
| 2026-02-10 | 实验室版开始使用 |
| 2026-03-21 | OML 版开发启动 |
| 2026-03-23 | OML 版完成，实验室版存档 |
| 2026-03-23 | 建议所有用户迁移到 OML 版 |

---

## 🆘 获取帮助

- **迁移问题**: 查看 [更新指南](../docs/UPDATE-QWENX-GUIDE.md)
- **配置问题**: 查看 [配置指南](../docs/QWENX-CONFIG-GUIDE.md)
- **GitHub Issues**: https://github.com/your-org/oh-my-litecode/issues

---

**维护者**: OML Team  
**存档日期**: 2026-03-23  
**许可**: MIT License
