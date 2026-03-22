# 实验室版 qwenx 迁移指南

**适用**: 从实验室版迁移到 OML 版  
**日期**: 2026-03-23

---

## 📋 迁移前检查

### 1. 备份现有配置

```bash
# 创建备份目录
BACKUP_DIR="$HOME/qwenx-legacy-backup.$(date +%Y%m%d_%H%M%S)"
mkdir -p "$BACKUP_DIR"

# 备份配置
cp -r ~/.local/home/qwenx/.qwen "$BACKUP_DIR/"
cp -r ~/.local/home/qwenx/.qwenx "$BACKUP_DIR/"

# 备份命令
if [[ -f /usr/bin/qwenx ]]; then
    cp /usr/bin/qwenx "$BACKUP_DIR/qwenx.backup"
fi

echo "备份完成：$BACKUP_DIR"
```

### 2. 记录当前状态

```bash
# 记录版本信息
qwenx --help 2>&1 | head -5

# 记录配置
cat ~/.local/home/qwenx/.qwen/settings.json

# 记录密钥
qwenx ctx7 list
```

---

## 🔄 迁移步骤

### 步骤 1: 安装 OML 系统

```bash
# 克隆仓库
mkdir -p ~/develop
cd ~/develop
git clone https://github.com/your-org/oh-my-litecode.git
cd oh-my-litecode

# 设置 PATH
export PATH="$HOME/develop/oh-my-litecode:$PATH"
echo 'export PATH="$HOME/develop/oh-my-litecode:$PATH"' >> ~/.bashrc
```

### 步骤 2: 运行迁移脚本

```bash
# 自动迁移
bash scripts/update-qwenx.sh
```

### 步骤 3: 迁移配置

```bash
# 迁移 Context7 密钥（保留）
cp "$BACKUP_DIR/.qwenx/secrets/context7.keys" \
   ~/.local/home/qwenx/.qwenx/secrets/ 2>/dev/null || true

# 迁移自定义配置（手动合并）
# 不要直接覆盖，需要检查配置差异
```

### 步骤 4: 配置 API 密钥

```bash
# 设置环境变量
echo 'export QWEN_API_KEY="sk-your-api-key"' >> ~/.bashrc
source ~/.bashrc

# 或使用 Context7
qwenx ctx7 set "ctx7sk-your-key@alias"
```

### 步骤 5: 验证迁移

```bash
# 基础验证
qwenx --oml-version
qwenx --oml-help

# 插件验证
oml plugins list

# 功能验证
qwenx session list
qwenx mcp list

# 健康检查
oml platform doctor
```

---

## ⚠️ 配置差异处理

### settings.json 变更

**实验室版**:
```json
{
  "mcpServers": {...},
  "model": {...}
}
```

**OML 版**:
```json
{
  "mcpServers": {...},
  "modelProviders": {
    "openai": [
      {
        "id": "qwen-plus",
        "name": "Qwen Plus",
        "envKey": "QWEN_API_KEY",
        "baseUrl": "https://dashscope.aliyuncs.com/compatible-mode/v1"
      }
    ]
  },
  "model": {...}
}
```

### 新增功能配置

```json
{
  "session": {
    "enabled": true
  },
  "hooks": {
    "enabled": true
  }
}
```

---

## 🔙 回滚步骤

如需回滚到实验室版：

```bash
# 1. 恢复旧版命令
sudo cp ~/qwenx-legacy-backup.*/qwenx.backup /usr/bin/qwenx
chmod +x /usr/bin/qwenx

# 2. 恢复配置
cp -r ~/qwenx-legacy-backup.*/.qwen ~/.local/home/qwenx/
cp -r ~/qwenx-legacy-backup.*/.qwenx ~/.local/home/qwenx/

# 3. 验证回滚
qwenx --help
```

---

## 📊 迁移检查清单

- [ ] 已创建完整备份
- [ ] 已记录当前状态
- [ ] OML 系统已安装
- [ ] 迁移脚本已运行
- [ ] 配置已迁移
- [ ] API 密钥已配置
- [ ] 所有验证通过
- [ ] 了解回滚方法

---

## 🆘 常见问题

### Q: 迁移后配置丢失

**A**: 从备份恢复配置
```bash
cp ~/qwenx-legacy-backup.*/.qwen/settings.json \
   ~/.local/home/qwenx/.qwen/
```

### Q: Context7 密钥不生效

**A**: 检查密钥文件权限
```bash
chmod 600 ~/.local/home/qwenx/.qwenx/secrets/context7.keys
qwenx ctx7 current
```

### Q: 命令找不到

**A**: 检查 PATH
```bash
export PATH="$HOME/develop/oh-my-litecode:$PATH"
source ~/.bashrc
```

---

## 📚 相关文档

- [更新指南](../docs/UPDATE-QWENX-GUIDE.md)
- [配置指南](../docs/QWENX-CONFIG-GUIDE.md)
- [存档说明](README.md)

---

**维护者**: OML Team  
**许可**: MIT License
