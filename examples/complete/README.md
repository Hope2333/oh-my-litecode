# 完整使用示例

## 场景：完整的 OML 工作流程

### 1. 初始化项目

```bash
# 创建项目目录
mkdir my-project && cd my-project

# 初始化 OML 配置
mkdir -p .oml
```

### 2. 配置自动备份

```typescript
import { AutoBackup } from '@oml/modules/backup';

const backup = new AutoBackup({
  dataDir: './.oml',
  sourceDir: '.',
  config: {
    intervalHours: 24,
    maxBackups: 7,
    excludePatterns: ['**/node_modules/**', '**/.git/**'],
  },
});

// 启动自动备份
backup.start();
```

### 3. 使用 Session 管理

```typescript
import { SessionManager } from '@oml/core/session';

const manager = new SessionManager({ sessionsDir: './.oml/sessions' });

// 创建会话
const session = await manager.create({ name: 'my-work-session' });

// 添加消息
await manager.addMessage('user', 'Help me write a function');
await manager.addMessage('assistant', 'Sure! Here is the function...');

// 搜索会话
const results = await manager.searchByKeyword('function');

// 使用缓存
const cached = await manager.getCachedSession(session.id);
```

### 4. 解决配置冲突

```typescript
import { ConflictResolver } from '@oml/modules/conflict';

const resolver = new ConflictResolver({ dataDir: './.oml' });

// 检测冲突
const conflict = resolver.detectConflict(
  'config.json',
  localConfig,
  remoteConfig
);

// 解决冲突
if (conflict) {
  const resolved = resolver.resolve(conflict.id, {
    strategy: 'merge', // or 'local' or 'remote'
  });
  console.log(`Resolved: ${resolved?.resolvedContent}`);
}
```

### 5. 国际化支持

```typescript
import { t, setLocale } from '@oml/modules/i18n';

// 设置语言
setLocale('zh-CN');

// 使用翻译
console.log(t('welcome')); // 欢迎
console.log(t('session.create')); // 创建会话

// 带参数的翻译
console.log(t('greeting', { name: 'World' }));
```

### 6. 性能监控

```typescript
import { PerfMonitor } from '@oml/modules/perf';

const monitor = new PerfMonitor({ dataDir: './.oml' });
monitor.init();

// 记录启动时间
const startTime = Date.now();
// ... initialization code ...
monitor.recordStartup(Date.now() - startTime);

// 生成性能报告
const report = await monitor.generateReport('24h');
console.log(`Performance Score: ${report.summary.score}/100`);
```

### 7. 使用 CLI 命令

```bash
# 插件管理
oml plugin list
oml plugin install my-plugin
oml plugin enable my-plugin

# 云同步
oml cloud auth --code <code>
oml cloud sync --direction push

# 性能监控
oml perf monitor --status
oml perf benchmark --name my-benchmark
oml perf report --period 24h
```
