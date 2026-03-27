# Shell -> TypeScript API 映射文档

**AI-LTC Lane**: shell-migration-research
**Stage**: 4 - Mapping
**Date**: 2026 年 3 月 26 日

---

## 1. 基础映射对照

### 1.1 变量映射

| Shell | TypeScript | 说明 |
|-------|------------|------|
| `$VAR` | `process.env.VAR` | 环境变量 |
| `${VAR:-default}` | `VAR ?? 'default'` | 默认值 |
| `$#` | `args.length` | 参数数量 |
| `$1, $2, $3` | `args[0], args[1], args[2]` | 位置参数 |
| `$@` | `...args` | 所有参数 |
| `$?` | `try/catch` | 退出码/错误 |
| `$$` | `process.pid` | 进程 ID |

### 1.2 控制流映射

| Shell | TypeScript | 说明 |
|-------|------------|------|
| `if [[ cond ]]; then` | `if (cond) {` | 条件判断 |
| `case $x in` | `switch (x) {` | 分支选择 |
| `for i in items; do` | `for (const i of items) {` | 循环 |
| `while [[ cond ]]; do` | `while (cond) {` | while 循环 |
| `function name() {` | `function name() {` | 函数定义 |

### 1.3 文件操作映射

| Shell | TypeScript | 说明 |
|-------|------------|------|
| `cat file` | `fs.readFile(file, 'utf-8')` | 读取文件 |
| `echo "x" > file` | `fs.writeFile(file, 'x')` | 写入文件 |
| `echo "x" >> file` | `fs.appendFile(file, 'x')` | 追加文件 |
| `rm file` | `fs.unlink(file)` | 删除文件 |
| `mkdir -p dir` | `fs.mkdir(dir, { recursive: true })` | 创建目录 |
| `[[ -f file ]]` | `fs.existsSync(file)` | 文件存在 |
| `[[ -d dir ]]` | `fs.statSync(dir).isDirectory()` | 目录存在 |

---

## 2. Session 模块映射

### 2.1 session-manager.sh -> SessionManager

```bash
# Shell: session-manager.sh
session_create() {
    local name="${1:-}"
    local session_id="qwen-session-$(date +%s)-$$-${RANDOM}"
    
    # Create session data
    local session_data=$(python3 -c "
import json
print(json.dumps({
    'session_id': '${session_id}',
    'name': '${name}',
    'status': 'active',
    'created_at': '$(date -Iseconds)'
}))
")
    
    echo "$session_data" > "${QWEN_SESSION_DIR}/${session_id}.json"
    echo "$session_id"
}
```

```typescript
// TypeScript: SessionManager.ts
async create(options?: SessionCreateOptions): Promise<Session> {
  const session: Session = {
    id: `qwen-session-${Date.now()}-${process.pid}-${randomId()}`,
    name: options?.name,
    status: 'active',
    createdAt: new Date(),
    updatedAt: new Date(),
    messages: [],
    metadata: options?.metadata || {},
  };

  await this.storage.save(session);
  return session;
}
```

### 2.2 函数映射表

| Shell 函数 | TypeScript 方法 | 参数 | 返回值 |
|-----------|----------------|------|--------|
| `session_create [name]` | `create(options)` | name?: string | session_id |
| `session_resume [id]` | `resume(id?)` | id?: string | Session |
| `session_switch <id>` | `switch(id)` | id: string | void |
| `session_list [limit]` | `list(options)` | limit?: number | Session[] |
| `session_delete <id>` | `delete(id)` | id: string | void |

---

## 3. Pool 模块映射

### 3.1 pool-manager.sh -> PoolManager

```bash
# Shell: pool-manager.sh
pool_create() {
    local name="$1"
    local max_size="${2:-10}"
    local min_size="${3:-1}"
    
    POOLS["$name"]="{
        \"max_size\": $max_size,
        \"min_size\": $min_size,
        \"active\": 0,
        \"idle\": 0
    }"
}

pool_acquire() {
    local name="$1"
    local timeout="${2:-30}"
    
    # Wait for available resource
    # ...
}
```

```typescript
// TypeScript: PoolManager.ts
class PoolManager<T> {
  constructor(config: PoolConfig) {
    this.config = {
      maxSize: config.maxSize ?? 10,
      minSize: config.minSize ?? 1,
      // ...
    };
  }

  async acquire(): Promise<T> {
    // Wait for available resource
    // ...
  }

  async release(resource: T): Promise<void> {
    // ...
  }
}
```

### 3.2 函数映射表

| Shell 函数 | TypeScript 方法 | 参数 | 返回值 |
|-----------|----------------|------|--------|
| `pool_create <name> [max] [min]` | `constructor(config)` | PoolConfig | PoolManager |
| `pool_acquire <name> [timeout]` | `acquire()` | - | Promise<T> |
| `pool_release <name> <resource>` | `release(resource)` | resource: T | Promise<void> |
| `pool_destroy <name>` | `destroy()` | - | Promise<void> |
| `pool_stats <name>` | `getStats()` | - | PoolStats |

---

## 4. Hooks 模块映射

### 4.1 hooks-engine.sh -> HooksEngine

```bash
# Shell: hooks-engine.sh
hook_register() {
    local event="$1"
    local name="$2"
    local handler="$3"
    local priority="${4:-10}"
    
    HOOKS["$event"]+="$name:$handler:$priority;"
}

hook_trigger() {
    local event="$1"
    shift
    local data="$*"
    
    for hook in ${HOOKS["$event"]}; do
        # Execute hook
        # ...
    done
}
```

```typescript
// TypeScript: HooksEngine.ts
class HooksEngine {
  register(event: HookEvent, handler: HookHandler): void {
    this.registry.register(event, handler);
  }

  async trigger(event: HookEvent, data: Record<string, unknown> = {}): Promise<void> {
    const handlers = this.registry.get(event);
    for (const handler of handlers) {
      await handler.execute({ event, data, timestamp: new Date() });
    }
  }
}
```

### 4.2 函数映射表

| Shell 函数 | TypeScript 方法 | 参数 | 返回值 |
|-----------|----------------|------|--------|
| `hook_register <event> <name> <handler> [priority]` | `register(event, handler)` | event, handler | void |
| `hook_trigger <event> [data...]` | `trigger(event, data)` | event, data | Promise<void> |
| `hook_unregister <name>` | `unregister(name)` | name | void |
| `hook_enable <name>` | `enableHook(name)` | name | void |
| `hook_disable <name>` | `disableHook(name)` | name | void |

---

## 5. 配置映射

### 5.1 环境变量

| Shell | TypeScript | 说明 |
|-------|------------|------|
| `QWEN_SESSION_DIR` | `process.env.QWEN_SESSION_DIR` | Session 目录 |
| `QWEN_API_KEY` | `process.env.QWEN_API_KEY` | API 密钥 |
| `HOME` | `process.env.HOME` | Home 目录 |

### 5.2 配置文件

```bash
# Shell: 读取配置
source "${QWEN_CONFIG_DIR}/settings.json" 2>/dev/null || true
```

```typescript
// TypeScript: 读取配置
const config = JSON.parse(
  fs.readFileSync(configPath, 'utf-8')
);
```

---

## 6. 错误处理映射

### 6.1 退出码 -> Error 类

```bash
# Shell
if [[ ! -f "$session_file" ]]; then
    echo "Session not found: $session_id" >&2
    return 1
fi
```

```typescript
// TypeScript
if (!await this.storage.exists(sessionId)) {
    throw new SessionNotFoundError(sessionId);
}
```

### 6.2 Error 类层次

```typescript
// 基础错误
class OMLError extends Error {
  constructor(message: string, public code: string) {
    super(message);
  }
}

// Session 错误
class SessionError extends OMLError {
  constructor(message: string, public sessionId?: string) {
    super(message, 'SESSION_ERROR');
  }
}

class SessionNotFoundError extends SessionError {
  constructor(sessionId: string) {
    super(`Session not found: ${sessionId}`, sessionId);
  }
}

// Pool 错误
class PoolError extends OMLError {
  constructor(message: string, public poolName?: string) {
    super(message, 'POOL_ERROR');
  }
}
```

---

## 7. 完整迁移示例

### 7.1 示例：session-list

**Shell 实现**:
```bash
session_list() {
    local limit="${1:-10}"
    
    if [[ ! -d "$QWEN_SESSION_DIR" ]]; then
        echo "No sessions found"
        return 0
    fi
    
    local count=0
    for session_file in "$QWEN_SESSION_DIR"/*.json; do
        if [[ $count -ge $limit ]]; then
            break
        fi
        
        local session_data=$(cat "$session_file")
        local session_id=$(echo "$session_data" | python3 -c "import sys,json; print(json.load(sys.stdin)['session_id'])")
        local name=$(echo "$session_data" | python3 -c "import sys,json; print(json.load(sys.stdin).get('name', 'unnamed'))")
        
        printf "%-40s %-20s\n" "$session_id" "$name"
        ((count++))
    done
    
    echo "Total: $count sessions"
}
```

**TypeScript 实现**:
```typescript
async list(options?: SessionListOptions): Promise<Session[]> {
  const sessions = await this.storage.list();
  
  let result = sessions;
  if (options?.limit) {
    result = sessions.slice(0, options.limit);
  }
  
  return result;
}

// CLI 命令
session
  .command('list')
  .description('List sessions')
  .option('-l, --limit <number>', 'Limit results', '10')
  .action(async (options) => {
    const limit = parseInt(options.limit, 10);
    const sessions = await manager.list({ limit });
    
    if (sessions.length === 0) {
      console.log('No sessions found');
      return;
    }
    
    console.log('Sessions:');
    for (const s of sessions) {
      console.log(`  ${s.id} - ${s.name || 'unnamed'} (${s.status})`);
    }
    console.log(`Total: ${sessions.length} sessions`);
  });
```

---

## 8. 迁移注意事项

### 8.1 异步处理

Shell 是同步执行，TypeScript 需要处理异步：

```bash
# Shell (同步)
result=$(some_command)
process_result "$result"
```

```typescript
// TypeScript (异步)
const result = await someCommand();
await processResult(result);
```

### 8.2 错误传播

```bash
# Shell
set -e  # 遇到错误立即退出
some_command || echo "Command failed"
```

```typescript
// TypeScript
try {
  await someCommand();
} catch (error) {
  console.error('Command failed:', error);
}
```

### 8.3 资源清理

```bash
# Shell
trap 'cleanup' EXIT
```

```typescript
// TypeScript
try {
  // ...
} finally {
  await cleanup();
}
```

---

**Next Stage**: Stage 5 - 指南阶段，产出 `MIGRATION-GUIDE.md`
