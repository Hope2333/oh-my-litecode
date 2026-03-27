# @oml/core

OML (Oh-My-Litecode) Core 包 - 核心功能模块

## 安装

```bash
npm install @oml/core
```

## 使用

### 日志系统

```typescript
import { Logger, info, error } from '@oml/core';

// 创建 logger
const logger = new Logger({ name: 'my-app', level: 'info' });

logger.info('Application started');
logger.error('Something went wrong');

// 或使用便捷函数
info('Quick log');
error('Quick error');

// 创建子 logger
const childLogger = logger.child('module');
```

### 平台检测

```typescript
import { PlatformDetector, detectPlatform, getPlatformInfo } from '@oml/core';

// 使用默认检测器
const platform = detectPlatform();
console.log(`Running on: ${platform}`);

// 或使用完整信息
const info = await getPlatformInfo();
console.log(info);

// 或创建自定义检测器
const detector = new PlatformDetector();
const platformInfo = await detector.getPlatformInfo();
```

### 配置系统

```typescript
import { ConfigLoader, loadConfig } from '@oml/core';

// 加载配置
const config = await loadConfig();
console.log(config.projectName);

// 或使用自定义加载器
const loader = new ConfigLoader('/path/to/config.json');
const myConfig = await loader.load();
```

## API

### Logger

- `Logger(options)` - 创建 logger 实例
- `debug(message)` - 调试日志
- `info(message)` - 信息日志
- `warn(message)` - 警告日志
- `error(message)` - 错误日志
- `child(name)` - 创建子 logger

### PlatformDetector

- `detectPlatform()` - 检测平台类型
- `detectArch()` - 检测架构
- `detectFakeHomeNesting()` - 检测 fakehome 嵌套
- `fixFakeHomeNesting()` - 修复 fakehome 嵌套
- `getPlatformInfo()` - 获取完整平台信息

### ConfigLoader

- `load()` - 加载配置
- `reload()` - 重新加载配置
- `getConfig()` - 获取已加载配置
- `get(key)` - 获取配置项
- `update(key, value)` - 更新配置项

## 开发

```bash
# 开发模式
npm run dev

# 构建
npm run build

# 测试
npm run test

# 类型检查
npm run typecheck

# 清理
npm run clean
```

## 许可证

MIT
