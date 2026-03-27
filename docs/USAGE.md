# OML 使用指南

## CLI 命令

### 插件管理 (`oml plugin`)

```bash
# 列出所有插件
oml plugin list

# 安装插件
oml plugin install <source>

# 卸载插件
oml plugin uninstall <name>

# 启用/禁用插件
oml plugin enable <name>
oml plugin disable <name>

# 运行插件
oml plugin run <name> [args...]

# 查看插件信息
oml plugin info <name>
```

### 云同步 (`oml cloud`)

```bash
# 认证
oml cloud auth --code <code>

# 同步
oml cloud sync --direction <pull|push|status>

# 查看状态
oml cloud status

# 查看配置
oml cloud config
```

### 性能监控 (`oml perf`)

```bash
# 监控
oml perf monitor --status
oml perf monitor --start
oml perf monitor --stop

# 基准测试
oml perf benchmark --name <name>

# 生成报告
oml perf report --period <period>

# 优化
oml perf optimize
```

### Qwen 控制器 (`oml qwen`)

```bash
# 聊天
oml qwen chat [query]

# 会话管理
oml qwen session list
oml qwen session create [name]
oml qwen session switch <id>
oml qwen session delete <id>

# 密钥管理
oml qwen keys list
oml qwen keys add <key> [@alias]
oml qwen keys rotate
```

## 模块使用示例

### Auto Backup

```typescript
import { AutoBackup } from '@oml/modules/backup';

const backup = new AutoBackup({ dataDir: './.oml', sourceDir: '.' });

// 启动自动备份
backup.start();

// 运行备份
const result = await backup.run();

// 恢复备份
await backup.restore(backupId);
```

### Conflict Resolver

```typescript
import { ConflictResolver } from '@oml/modules/conflict';

const resolver = new ConflictResolver({ dataDir: './.oml' });

// 检测冲突
const conflict = resolver.detectConflict('config.json', local, remote);

// 解决冲突
resolver.resolve(conflict.id, { strategy: 'local' });
```

### I18n

```typescript
import { t, setLocale } from '@oml/modules/i18n';

// 设置语言
setLocale('zh-CN');

// 翻译
console.log(t('welcome')); // 欢迎
console.log(t('session.create')); // 创建会话
```

### Performance Monitor

```typescript
import { PerfMonitor } from '@oml/modules/perf';

const monitor = new PerfMonitor({ dataDir: './.oml' });
monitor.init();

// 记录启动时间
monitor.recordStartup(100);

// 生成报告
const report = await monitor.generateReport('24h');
```

## 高级功能

### Pool 持久化

```typescript
import { PoolManager } from '@oml/core/pool';

const pool = new PoolManager({ config: { minWorkers: 1, maxWorkers: 4 } });
await pool.init();

// 保存状态
await pool.saveState('./pool-state.json');

// 加载状态
await pool.loadState('./pool-state.json');
```

### Session 索引和缓存

```typescript
import { SessionManager } from '@oml/core/session';

const manager = new SessionManager({ sessionsDir: './sessions' });

// 构建索引
const index = await manager.buildIndex();

// 关键字搜索
const sessions = await manager.searchByKeyword('hello');

// 缓存会话
const session = await manager.getCachedSession(sessionId);
```

## 验证

```bash
# 构建
npm run build

# 类型检查
npm run typecheck

# 测试
npm test
```
