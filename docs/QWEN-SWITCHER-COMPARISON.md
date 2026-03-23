# Qwen 切换器插件对比

**日期**: 2026-03-23

---

## 📊 快速对比表

| 特性 | Qwen Key Switcher | Qwen OAuth Switcher |
|------|------------------|---------------------|
| **插件名** | `qwen-key-switcher` | `qwen-oauth-switcher` |
| **命令** | `oml qwen-key` | `oml qwen-oauth` |
| **管理对象** | API Key (字符串) | OAuth 配置文件 (JSON) |
| **存储内容** | `sk-xxxxx` | `settings.json` 完整内容 |
| **切换方式** | 导出环境变量 | 复制配置文件 |
| **适用场景** | 多个免费 API Key | 多个 OAuth 登录账号 |
| **配置复杂度** | 简单 | 完整 |

---

## 🔑 Qwen Key Switcher

### 工作原理

```
存储多个 API Key → 导出到 QWEN_API_KEY → 使用
```

### 存储结构

```
~/.oml/qwen-keys/
├── keys.json       # Base64 编码的 API Key 列表
├── current         # 当前 Key 索引 (0, 1, 2...)
└── stats.json      # 使用统计
```

### 使用示例

```bash
# 添加 API Key
oml qwen-key add sk-free123456789 work

# 列出 Key
oml qwen-key list
# 输出：
#   0: work
#       Key: sk-***abcd

# 切换 Key
oml qwen-key use 0

# 导出到环境变量
eval $(oml qwen-key export)
# 输出：
# export QWEN_API_KEY='sk-free123456789'
# export QWEN_BASE_URL='...'
```

### 适用场景

✅ **适合以下情况**：
- 你有多个免费的 Qwen API Key
- 只需要切换 API Key
- 不需要完整的 OAuth 配置
- 想要简单的 Key 管理

❌ **不适合**：
- 需要切换完整的 OAuth 账号
- 需要保存完整的 settings.json 配置

---

## 🔐 Qwen OAuth Switcher

### 工作原理

```
存储多个 settings.json → 复制到 Qwen 配置目录 → 实现账号切换
```

### 存储结构

```
~/.oml/qwen-oauth/
├── accounts/
│   ├── work/settings.json       # 工作账号完整配置
│   └── personal/settings.json   # 个人账号完整配置
├── current                      # 当前账号名称
└── backups/
    └── 20260323_120000/         # 配置备份
```

### 使用示例

```bash
# 添加 OAuth 账号（交互式）
oml qwen-oauth add work
# 提示：粘贴 settings.json 内容

# 导入现有配置
oml qwen-oauth import personal ~/.local/home/qwenx/.qwen/settings.json

# 列出账号
oml qwen-oauth list
# 输出：
# * work
#       Added: 2026-03-23T10:00:00+08:00
# 
#   personal
#       Added: 2026-03-23T10:01:00+08:00

# 切换账号
oml qwen-oauth use work
# 执行：
# cp accounts/work/settings.json ~/.local/home/qwenx/.qwen/settings.json
```

### 适用场景

✅ **适合以下情况**：
- 你有多个 Qwen 登录账号
- 每个账号有完整的 settings.json 配置
- 需要保存完整的 OAuth 配置
- 想要备份和恢复配置

❌ **不适合**：
- 只有 API Key，没有完整配置
- 想要简单的 Key 管理

---

## 📋 详细对比

### 1. 管理对象

| 项目 | Key Switcher | OAuth Switcher |
|------|-------------|----------------|
| **类型** | 字符串 | JSON 文件 |
| **内容** | `sk-xxxxx` | 完整 settings.json |
| **大小** | ~100 bytes | ~1-5 KB |
| **数量** | 无限制 | 无限制 |

### 2. 切换方式

| 项目 | Key Switcher | OAuth Switcher |
|------|-------------|----------------|
| **方式** | 环境变量 | 文件复制 |
| **速度** | 即时 | 即时 |
| **影响** | 当前 shell | Qwen 配置目录 |

### 3. 功能对比

| 功能 | Key Switcher | OAuth Switcher |
|------|-------------|----------------|
| **添加** | ✅ add | ✅ add (交互式) |
| **导入** | ❌ | ✅ import |
| **切换** | ✅ use | ✅ use |
| **轮询** | ✅ rotate | ✅ rotate |
| **备份** | ❌ | ✅ backup/restore |
| **统计** | ✅ stats | ❌ |
| **健康检查** | ✅ health | ❌ |

### 4. 安全性

| 特性 | Key Switcher | OAuth Switcher |
|------|-------------|----------------|
| **加密** | Base64 | 无 (原始 JSON) |
| **权限** | 600/700 | 600/700 |
| **掩码显示** | ✅ sk-***abcd | ❌ 完整显示 |

---

## 🎯 选择建议

### 选择 Key Switcher，如果你：

1. ✅ 只有 API Key，没有完整配置
2. ✅ 想要简单的 Key 管理
3. ✅ 需要使用统计和健康检查
4. ✅ 经常切换 Key（轮询功能）

### 选择 OAuth Switcher，如果你：

1. ✅ 有多个完整的 settings.json 配置
2. ✅ 需要备份和恢复配置
3. ✅ 想要导入现有配置
4. ✅ 需要保存完整的 OAuth 设置

### 两个都用，如果你：

1. ✅ 既有 API Key 又有完整配置
2. ✅ 需要灵活的管理方式

---

## 💡 组合使用示例

```bash
# 使用 OAuth Switcher 管理账号
oml qwen-oauth add work
oml qwen-oauth add personal

# 切换到工作账号
oml qwen-oauth use work

# 使用 Key Switcher 管理额外的 API Key
oml qwen-key add sk-extra1 backup1
oml qwen-key add sk-extra2 backup2

# 当 OAuth 账号限额用完时，切换到备用 Key
oml qwen-key use 0
```

---

## 📊 性能对比

| 指标 | Key Switcher | OAuth Switcher |
|------|-------------|----------------|
| **启动时间** | <10ms | <10ms |
| **切换时间** | <10ms | <50ms (文件复制) |
| **存储占用** | <1 KB | 每个账号 1-5 KB |
| **内存占用** | <1 MB | <1 MB |

---

## 🔗 相关文档

- [Key Switcher 指南](QWEN-KEY-SWITCHER-GUIDE.md)
- [OAuth Switcher 指南](QWEN-OAUTH-SWITCHER-GUIDE.md)
- [Qwen Agent 插件](../plugins/agents/qwen/)

---

**维护者**: OML Team  
**日期**: 2026-03-23
