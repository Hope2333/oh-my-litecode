# 性能优化示例

## 运行基准测试

```bash
node examples/perf/benchmark.js
```

## 缓存优化

### Session 缓存

```typescript
import { SessionManager } from '@oml/core/session';

const manager = new SessionManager({ sessionsDir: './sessions' });

// 使用缓存获取会话
const session = await manager.getCachedSession(sessionId);

// 清除缓存
manager.clearCache();

// 设置缓存 TTL (默认 5 分钟)
manager.setCacheTTL(600000);
```

### Pool 状态持久化

```typescript
import { PoolManager } from '@oml/core/pool';

const pool = new PoolManager({ config: { minWorkers: 1, maxWorkers: 4 } });
await pool.init();

// 保存状态
await pool.saveState('./pool-state.json');

// 加载状态
await pool.loadState('./pool-state.json');
```

## 性能监控

```typescript
import { PerfMonitor } from '@oml/modules/perf';

const monitor = new PerfMonitor({ dataDir: './.oml' });
monitor.init();

// 记录操作
monitor.recordStartup(100); // ms
monitor.recordCommandLatency(50); // ms

// 生成报告
const report = await monitor.generateReport('24h');
console.log(`Score: ${report.summary.score}/100`);
```

## 优化建议

1. **启用 Session 缓存**: 减少重复数据库查询
2. **使用 Pool 持久化**: 避免重启后重新初始化
3. **定期清理旧数据**: 使用 AutoBackup 的清理功能
4. **监控性能指标**: 使用 PerfMonitor 跟踪性能变化
