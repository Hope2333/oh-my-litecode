# OML Hooks Engine 使用指南

## 概述

OML Hooks Engine 是一个完整的事件驱动 Hooks 系统，支持：
- 事件发布/订阅
- Hook 注册与管理
- 阻塞/非阻塞模式
- 超时控制
- 完整的错误处理

## 模块结构

```
core/
├── event-bus.sh          # 事件总线核心
├── hooks-registry.sh     # Hooks 注册表管理
├── hooks-dispatcher.sh   # 事件分发器
└── hooks-engine.sh       # Hooks 引擎主逻辑

plugins/core/hooks-runtime/
├── main.sh               # 运行时插件入口
├── plugin.json           # 插件元数据
├── lib/                  # 导出接口
│   ├── event-bus-exports.sh
│   ├── registry-exports.sh
│   ├── dispatcher-exports.sh
│   └── engine-exports.sh
├── scripts/              # 安装/卸载脚本
└── examples/             # 使用示例
```

## 快速开始

### 1. 初始化 Hooks 引擎

```bash
# Source 核心模块
source /path/to/core/hooks-engine.sh

# 或使用 CLI
./oml hooks init
```

### 2. 注册 Hook

```bash
# 注册 Pre-hook（在目标操作之前执行）
oml hooks add pre build:start /path/to/pre-build.sh 10

# 注册 Post-hook（在目标操作之后执行）
oml hooks add post build:complete /path/to/post-build.sh 5

# 注册 Around-hook（包围目标操作）
oml hooks add around git:commit /path/to/around-commit.sh 0
```

### 3. 触发 Hook

```bash
# 阻塞模式（默认）
oml hooks trigger build:start

# 带超时
oml hooks trigger build:start --timeout 60

# 遇到错误立即停止
oml hooks trigger deploy:start --stop-on-error

# 并行执行所有 Hooks
oml hooks trigger test:run --parallel

# 非阻塞模式（后台执行）
oml hooks trigger async:event --async
```

### 4. 管理 Hook

```bash
# 列出所有 Hooks
oml hooks list

# 按事件过滤
oml hooks list build

# 按状态过滤
oml hooks list "" enabled
oml hooks list "" disabled

# 启用/禁用 Hook
oml hooks enable pre-build
oml hooks disable pre-build

# 移除 Hook
oml hooks remove pre build:start
```

## 编程接口

### 在脚本中使用

```bash
#!/usr/bin/env bash
set -eo pipefail

# Source 核心模块
source /path/to/core/hooks-engine.sh

# 初始化
oml_hooks_engine_init

# 注册 Hook
oml_hook_add "pre" "myapp:start" "/path/to/hook.sh" 10

# 触发 Hook
oml_hook_trigger "myapp:start" "arg1" "arg2"

# 或使用底层 API
oml_event_emit "myapp:start:pre" "arg1" "arg2"
# ... 执行主操作 ...
oml_event_emit "myapp:start:post" "arg1" "arg2"
```

### 在插件中使用

```bash
#!/usr/bin/env bash
set -eo pipefail

# Source 运行时导出
source /path/to/plugins/core/hooks-runtime/lib/engine-exports.sh

# 初始化
oml_init_hooks

# 注册 Hook
plugin_hook_pre "plugin:install" "/path/to/pre-install.sh"
plugin_hook_post "plugin:install" "/path/to/post-install.sh"

# 触发 Hook
plugin_trigger "plugin:install" "$PLUGIN_NAME"
```

## Hook 处理器示例

### Pre-build Hook

```bash
#!/usr/bin/env bash
# examples/pre-build.sh
set -euo pipefail

echo "[HOOK] Pre-build check starting..."

# 检查依赖
for dep in git make python3; do
    if ! command -v "$dep" >/dev/null 2>&1; then
        echo "[HOOK] ERROR: Missing dependency: $dep"
        exit 1
    fi
done

# 备份当前状态
backup_dir="${HOME}/.oml/hooks/backups"
mkdir -p "$backup_dir"
tar -czf "${backup_dir}/pre-build-$(date +%s).tar.gz" -C "${HOME}" ".oml" 2>/dev/null || true

echo "[HOOK] Pre-build check completed"
exit 0
```

### Post-build Hook

```bash
#!/usr/bin/env bash
# examples/post-build.sh
set -euo pipefail

build_status="${1:-success}"

echo "[HOOK] Post-build tasks starting..."

if [[ "$build_status" == "success" ]]; then
    # 清理临时文件
    rm -rf "${HOME}/.oml/tmp"/*
    
    # 发送通知
    echo "[HOOK] Build completed successfully"
else
    echo "[HOOK] Build failed with status: $build_status"
fi

exit 0
```

## 事件命名约定

```
命名空间：动作：子动作
例如：
  - build:start:pre      # 构建开始的 pre-hook
  - build:start:post     # 构建开始的 post-hook
  - plugin:install       # 插件安装事件
  - git:commit:around    # Git 提交的 around-hook
```

## 优先级说明

- 数值越大优先级越高
- 推荐范围：-1000 到 1000
- 高优先级 Hook 先执行
- 默认优先级：0

## 超时控制

```bash
# 设置全局超时
export OML_DISPATCHER_DEFAULT_TIMEOUT=60

# 或在触发时指定
oml hooks trigger build:start --timeout 120
```

## 错误处理

```bash
# 遇到错误立即停止
oml hooks trigger deploy:start --stop-on-error

# 检查退出码
if oml hooks trigger build:start; then
    echo "Hooks executed successfully"
else
    echo "Hooks failed"
    exit 1
fi
```

## 导入/导出配置

```bash
# 导出 Hooks 配置
oml hooks export ~/hooks-backup.json

# 导入 Hooks 配置
oml hooks import ~/hooks-backup.json

# 合并模式（默认）
oml hooks import ~/hooks-backup.json true

# 覆盖模式
oml hooks import ~/hooks-backup.json false
```

## 健康检查

```bash
# 运行健康检查
oml hooks health

# 查看状态
oml hooks status

# 清理资源
oml hooks cleanup --all
```

## CLI 参考

### oml event-bus

```
init                        初始化事件总线
on <event> <handler>        注册事件监听器
once <event> <handler>      注册一次性事件监听器
off <event> [handler]       移除事件监听器
emit <event> [args]         发布事件
emit-wait <event> [args]    发布事件并等待完成
stats                       显示统计信息
list [event]                列出已注册的监听器
```

### oml hooks-registry

```
init                        初始化注册表
register <name> <event> <handler> [priority]
                            注册 Hook
unregister <name>           注销 Hook
enable <name>               启用 Hook
disable <name>              禁用 Hook
info <name> [format]        获取 Hook 信息
list [event] [status]       列出 Hooks
stats                       显示统计信息
validate                    验证注册表完整性
```

### oml hooks-dispatcher

```
init                        初始化分发器
dispatch <event> [args]     分发事件到所有 Hooks
dispatch-single <hook>      分发到单个 Hook
history [limit]             查看分发历史
status                      显示分发器状态
```

### oml hooks

```
init                        初始化 Hooks 引擎
add <type> <target> <handler> [priority]
                            注册 Hook
remove <type> <target>      移除 Hook
trigger <target> [args]     触发目标的所有 Hooks
around-exec <target> <cmd>  执行带 Around Hook 的命令
status                      显示引擎状态
health                      健康检查
cleanup                     清理资源
export <file>               导出配置
import <file>               导入配置
```

## 已知限制

1. 在 Termux bash 5.3.9 中，关联数组与 `set -u` 选项存在兼容性问题
2. 事件名称中避免使用纯数字开头
3. 处理器函数名避免与 bash 内置命令冲突（如 `test`）

## 故障排除

### Hook 未执行

1. 检查 Hook 是否已启用：`oml hooks list "" enabled`
2. 检查事件名称是否匹配
3. 查看日志：`~/.oml/hooks/engine.log`

### 超时错误

1. 增加超时时间：`--timeout 120`
2. 检查处理器是否阻塞
3. 使用并行模式：`--parallel`

### 注册失败

1. 检查处理器路径是否正确
2. 检查处理器是否可执行：`chmod +x /path/to/hook.sh`
3. 验证事件名称格式
