# Fakehome 策略文档

## 背景

Qwen Code 使用 fakehome 机制来隔离不同 agent 的配置：
- 默认路径：`~/.local/home/qwenx` (qwenx) 或 `~/.local/home/qwen` (qwen 插件)
- 每个 fakehome 包含独立的 `.qwen`, `.cache`, `.npm` 等配置目录

## 问题

### 嵌套 Fakehome

当在 fakehome 环境中再次启动 qwenx/qwen 命令时，可能产生嵌套：
```
/home/user/.local/home/qwenx/.local/home/qwen/
                                    ^ 嵌套的 fakehome
```

这会导致：
- OAuth 凭证路径错误
- 配置文件重复
- 数据不一致

## 当前解决方案

### 1. 自动检测与修复

**检测模式**:
- 嵌套：`*/.local/home/*/.local/home/*` → 自动修复
- 单层：`*/.local/home/*` → 保留（这是正常设计）

**修复逻辑** (`core/fakehome-fix.sh`):
```bash
if [[ "${HOME}" == *"/.local/home/"*"/.local/home/"* ]]; then
    # 嵌套 fakehome，修复为外层
    HOME=$(echo "$HOME" | sed 's|/\.local/home/[^/]*$||')
fi
```

### 2. 清理脚本

`scripts/cleanup-fakehome.sh`:
- 只清理嵌套的 fakehome
- 保留正在运行的环境
- 合并数据到正确位置

### 3. 应用位置

- `oml`: 启动时自动检测
- `plugins/agents/qwen/main.sh`: qwen 插件启动时检测
- `core/platform.sh`: 集成 fakehome 修复模块

## 目录结构

### 正常结构（保留）
```
/home/user/
├── .local/home/
│   ├── qwenx/          # qwenx 的 fakehome (保留)
│   │   ├── .qwen/
│   │   └── .qwenx/
│   └── qwen/           # qwen 插件的 fakehome (保留)
│       └── .qwen/
└── .qwen/              # 全局配置
```

### 嵌套结构（清理）
```
/home/user/.local/home/qwenx/
└── .local/home/        # 嵌套的 .local (清理)
    └── qwen/           # 嵌套的 fakehome (清理/合并)
```

## 未来改进方向

### 方案 A: 环境变量传递
在 fakehome 环境中设置标志，避免重复创建 fakehome：
```bash
export _QWEN_FAKEHOME_ACTIVE=1
```

### 方案 B: 统一配置目录
使用单一配置目录，通过命名空间隔离：
```
~/.qwenx/
├── sessions/
├── secrets/
└── config/
```

### 方案 C: 容器化隔离
使用轻量级容器或 namespace 隔离，而非路径隔离。

## 最佳实践

1. **不要在 fakehome 内再次启动 qwenx**
   - 使用真实 home 目录启动

2. **定期清理嵌套**
   ```bash
   bash ~/develop/oh-my-litecode/scripts/cleanup-fakehome.sh
   ```

3. **检查当前状态**
   ```bash
   echo $HOME
   find ~/.local/home -type d -name ".local"
   ```

## 参考

- [Qwen Code 官方文档](https://qwenlm.github.io/qwen-code-docs/)
- [Qwen Code 扩展系统](https://qwenlm.github.io/qwen-code-docs/zh/users/extension/introduction/)
