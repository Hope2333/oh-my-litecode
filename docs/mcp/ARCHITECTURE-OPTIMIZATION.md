# MCP 架构优化路线图 | Architecture Optimization Roadmap

> **版本**: 1.0.0 | **标签**: [GENERIC] [PLANNING]

---

## 📋 概述

本文档描述 Qwen Code 递归子代理架构的完整优化路线图，按优先级分为 P0/P1/P2 三个阶段。

### 优化建议总览

| 维度 | 当前状态 | 优化潜力 | 优先级 | 预计工时 |
|------|----------|----------|--------|----------|
| **安全性** | 基础隔离 | 需加密/审计/权限 | P0 | 2 周 |
| **性能** | 顺序执行 | 并发 + 懒加载 3-5x | P0 | 2 周 |
| **容错** | 基础错误处理 | 重试/回滚/降级 | P0 | 2 周 |
| **可观测** | 基础日志 | 监控/告警/追踪 | P1 | 3 周 |
| **用户体验** | CLI 复杂 | 简化 50%+ | P1 | 2 周 |
| **扩展性** | 脚本耦合 | 插件化/配置化 | P2 | 3 周 |

---

## P0 关键优化（4-6 周）

### 1. 安全性加固 ⭐⭐⭐⭐⭐

#### 1.1 会话加密隔离

**文件**: `~/.oml/core/session-seal.sh`

```bash
#!/usr/bin/env bash
# 会话数据加密

set -euo pipefail

# 配置
SESSION_SEAL_ALGO="${SESSION_SEAL_ALGO:-aes-256-cbc}"

# 派生会话密钥
derive_session_key() {
    local session_id="$1"
    local master_key="${SESSION_MASTER_KEY:-}"
    
    if [[ -z "$master_key" ]]; then
        # 从硬件标识派生
        master_key=$(cat /proc/cpuinfo | md5sum | cut -d' ' -f1)
    fi
    
    # HKDF 派生
    echo -n "${session_id}${master_key}" | openssl dgst -sha256 -binary | xxd -p -c 64
}

# 加密会话数据
seal_session() {
    local session_id="$1"
    local data_file="$2"
    local output_file="${data_file}.sealed"
    
    local key=$(derive_session_key "$session_id")
    local iv=$(openssl rand -hex 16)
    
    openssl enc -${SESSION_SEAL_ALGO} \
        -in "$data_file" \
        -out "$output_file" \
        -K "$key" \
        -iv "$iv"
    
    echo "$iv" > "${data_file}.iv"
    chmod 600 "$output_file" "${data_file}.iv"
    
    echo "sealed:${output_file}"
}

# 解密会话数据
unseal_session() {
    local session_id="$1"
    local sealed_file="$2"
    local output_file="$3"
    
    local key=$(derive_session_key "$session_id")
    local iv=$(cat "${sealed_file%.sealed}.iv")
    
    openssl enc -d -${SESSION_SEAL_ALGO} \
        -in "$sealed_file" \
        -out "$output_file" \
        -K "$key" \
        -iv "$iv"
}
```

#### 1.2 审计日志系统

**文件**: `~/.oml/core/session-audit.py`

```python
#!/usr/bin/env python3
# 区块链式防篡改审计日志

import json
import hashlib
import os
import sys
from datetime import datetime
from pathlib import Path

class SessionAuditor:
    def __init__(self, audit_dir: str = None):
        self.audit_dir = Path(audit_dir or os.environ.get('OML_AUDIT_DIR', '~/.oml/audit'))
        self.audit_dir = Path(self.audit_dir.expanduser())
        self.audit_dir.mkdir(parents=True, exist_ok=True)
        self.current_hash = self._load_chain_hash()
    
    def _load_chain_hash(self) -> str:
        """加载区块链式哈希"""
        chain_file = self.audit_dir / 'chain.hash'
        if chain_file.exists():
            return chain_file.read_text().strip()
        return '0' * 64
    
    def _save_chain_hash(self, new_hash: str):
        """保存新哈希"""
        (self.audit_dir / 'chain.hash').write_text(new_hash)
    
    def log(self, event_type: str, session_id: str, operation: str, 
            details: dict = None, user_id: str = None):
        """记录审计事件"""
        timestamp = datetime.utcnow().isoformat() + 'Z'
        
        entry = {
            'timestamp': timestamp,
            'event_type': event_type,
            'session_id': session_id,
            'operation': operation,
            'user_id': user_id or os.environ.get('USER', 'unknown'),
            'pid': os.getpid(),
            'ppid': os.getppid(),
            'cwd': os.getcwd(),
            'details': details or {},
            'prev_hash': self.current_hash
        }
        
        entry_hash = hashlib.sha256(
            json.dumps(entry, sort_keys=True).encode()
        ).hexdigest()
        entry['entry_hash'] = entry_hash
        
        log_file = self.audit_dir / f'{datetime.utcnow().strftime("%Y%m%d")}.audit.jsonl'
        with open(log_file, 'a') as f:
            f.write(json.dumps(entry) + '\n')
        
        self.current_hash = entry_hash
        self._save_chain_hash(entry_hash)
        
        return entry_hash
```

#### 1.3 权限矩阵

| 操作 | 创建者 | 同组 (共享) | 其他 | 系统 |
|------|--------|-----------|------|------|
| CREATE | ✅ | ❌ | ❌ | ✅ |
| READ | ✅ | ✅ | ❌ | ✅ |
| UPDATE | ✅ | ❌ | ❌ | ✅ |
| DELETE | ✅ | ❌ | ❌ | ✅ |
| FORK | ✅ | ✅ | ❌ | ✅ |

---

### 2. 性能优化 ⭐⭐⭐⭐⭐

#### 2.1 并发执行框架

**文件**: `~/.oml/core/session-parallel.sh`

```bash
#!/usr/bin/env bash
# 并行会话操作框架

set -euo pipefail

# 配置
PARALLEL_WORKERS="${PARALLEL_WORKERS:-$(nproc)}"
PARALLEL_BATCH_SIZE="${PARALLEL_BATCH_SIZE:-10}"

# 并行处理会话列表
parallel_process_sessions() {
    local operation="$1"
    shift
    local sessions=("$@")
    local results_dir=$(mktemp -d)
    
    local -a pids=()
    local running=0
    
    for session_id in "${sessions[@]}"; do
        # 等待有空闲槽位
        while (( running >= PARALLEL_WORKERS )); do
            wait -n "${pids[@]}" 2>/dev/null || true
            pids=($(jobs -p))
            running=${#pids[@]}
            sleep 0.1
        done
        
        # 启动新任务
        (
            local result_file="${results_dir}/${session_id}.result"
            if $operation "$session_id" > "$result_file" 2>&1; then
                echo "success" > "${result_file}.status"
            else
                echo "failed" > "${result_file}.status"
            fi
        ) &
        pids+=($!)
        ((running++))
    done
    
    # 等待所有任务完成
    wait "${pids[@]}" 2>/dev/null || true
    
    # 收集结果
    local success=0
    local failed=0
    for status_file in "${results_dir}"/*.status; do
        if [[ -f "$status_file" ]]; then
            case $(cat "$status_file") in
                success) ((success++)) ;;
                failed) ((failed++)) ;;
            esac
        fi
    done
    
    echo "Completed: $success success, $failed failed"
    rm -rf "$results_dir"
}
```

#### 2.2 懒加载上下文

**文件**: `~/.oml/core/context-lazy-loader.py`

```python
#!/usr/bin/env python3
# LRU 缓存 + 按需加载

from functools import lru_cache
from pathlib import Path

class LazyContextLoader:
    def __init__(self, sessions_dir: str, cache_size: int = 100):
        self.sessions_dir = Path(sessions_dir)
        self.cache_size = cache_size
        self._cache = {}
    
    @lru_cache(maxsize=1000)
    def _get_session_path(self, session_id: str) -> Path:
        return self.sessions_dir / 'data' / f'{session_id}.json'
    
    def load_session(self, session_id: str, fields: list = None):
        """懒加载会话数据"""
        cache_key = f"{session_id}:{','.join(fields or [])}"
        
        if cache_key in self._cache:
            # 移动到最近使用
            self._cache.move_to_end(cache_key)
            return self._cache[cache_key]
        
        path = self._get_session_path(session_id)
        if not path.exists():
            raise FileNotFoundError(f"Session not found: {session_id}")
        
        with open(path) as f:
            full_data = json.load(f)
        
        if fields:
            data = {k: full_data.get(k) for k in fields}
        else:
            data = full_data
        
        # 更新缓存
        if len(self._cache) >= self.cache_size:
            self._cache.popitem(last=False)
        self._cache[cache_key] = data
        
        return data
```

#### 2.3 索引优化（布隆过滤器）

**文件**: `~/.oml/core/session-index.py`

```python
#!/usr/bin/env python3
# 布隆过滤器快速存在性检查

from pybloom_live import BloomFilter
from pathlib import Path

class OptimizedSessionIndex:
    def __init__(self, index_dir: str):
        self.index_dir = Path(index_dir)
        self.bloom_filter = BloomFilter(capacity=10000, error_rate=0.001)
        self.session_index = {}
    
    def build_index(self, sessions_dir: str):
        """构建优化索引"""
        sessions_path = Path(sessions_dir)
        
        for data_file in sessions_path.glob('*.json'):
            session_id = data_file.stem
            self.bloom_filter.add(session_id)
            
            self.session_index[session_id] = {
                'created_at': data_file.stat().st_mtime,
                'size': data_file.stat().st_size
            }
    
    def exists(self, session_id: str) -> bool:
        """O(1) 存在性检查"""
        return session_id in self.bloom_filter
```

---

### 3. 容错机制 ⭐⭐⭐⭐⭐

#### 3.1 智能重试框架

**文件**: `~/.oml/core/retry-framework.sh`

```bash
#!/usr/bin/env bash
# 指数退避 + 熔断器

set -euo pipefail

# 配置
RETRY_MAX_ATTEMPTS="${RETRY_MAX_ATTEMPTS:-5}"
RETRY_BASE_DELAY="${RETRY_BASE_DELAY:-1}"
RETRY_MAX_DELAY="${RETRY_MAX_DELAY:-60}"
RETRY_EXPONENT="${RETRY_EXPONENT:-2}"

# 计算延迟
calculate_delay() {
    local attempt="$1"
    local delay=$((RETRY_BASE_DELAY * (RETRY_EXPONENT ** (attempt - 1))))
    if (( delay > RETRY_MAX_DELAY )); then
        delay=$RETRY_MAX_DELAY
    fi
    echo "$delay"
}

# 重试执行
retry_execute() {
    local operation="$1"
    shift
    local attempt=1
    local last_error=""
    
    while (( attempt <= RETRY_MAX_ATTEMPTS )); do
        echo "Attempt $attempt/$RETRY_MAX_ATTEMPTS: $operation"
        
        if $operation "$@"; then
            echo "Success on attempt $attempt"
            return 0
        fi
        
        last_error=$?
        
        if (( attempt < RETRY_MAX_ATTEMPTS )); then
            local delay=$(calculate_delay "$attempt")
            echo "Failed, retrying in ${delay}s..."
            sleep "$delay"
        fi
        
        ((attempt++))
    done
    
    echo "All $RETRY_MAX_ATTEMPTS attempts failed"
    return "$last_error"
}
```

#### 3.2 回滚机制

**文件**: `~/.oml/core/session-rollback.sh`

```bash
#!/usr/bin/env bash
# 回滚点管理

set -euo pipefail

ROLLBACK_DIR="${ROLLBACK_DIR:-${HOME}/.oml/rollbacks}"

# 创建回滚点
create_rollback_point() {
    local session_id="$1"
    local operation="$2"
    local rollback_id="rb-$(date +%s)-$$"
    
    mkdir -p "$ROLLBACK_DIR"
    
    local data_path="${SESSION_DIR}/${session_id}.json"
    if [[ -f "$data_path" ]]; then
        cp "$data_path" "${ROLLBACK_DIR}/${rollback_id}.json"
        
        cat > "${ROLLBACK_DIR}/${rollback_id}.meta" <<EOF
rollback_id=${rollback_id}
session_id=${session_id}
operation=${operation}
created_at=$(date -Iseconds)
original_file=${data_path}
EOF
        
        echo "$rollback_id"
    fi
}

# 执行回滚
execute_rollback() {
    local rollback_id="$1"
    
    local meta_file="${ROLLBACK_DIR}/${rollback_id}.meta"
    local data_file="${ROLLBACK_DIR}/${rollback_id}.json"
    
    if [[ ! -f "$meta_file" ]] || [[ ! -f "$data_file" ]]; then
        echo "Rollback point not found: $rollback_id"
        return 1
    fi
    
    source "$meta_file"
    cp "$data_file" "$original_file"
    
    echo "Rollback completed: $rollback_id"
}
```

#### 3.3 降级策略

**文件**: `~/.oml/core/degradation-strategies.sh`

```bash
#!/usr/bin/env bash
# 系统负载高时自动降级

set -euo pipefail

# 降级级别
DEGRADATION_LEVEL="${DEGRADATION_LEVEL:-0}"

# 检查系统负载
check_system_load() {
    local load=$(cat /proc/loadavg | cut -d' ' -f1)
    local cpu_count=$(nproc)
    
    if (( $(echo "$load > $cpu_count * 2" | bc -l) )); then
        echo "high"
    else
        echo "normal"
    fi
}

# 应用降级策略
apply_degradation() {
    local level="$1"
    
    case "$level" in
        1)
            export SESSION_SUMMARY_ENABLED=false
            echo "Applied level 1 degradation: disabled summaries"
            ;;
        2)
            export SESSION_INDEX_UPDATE=false
            export PARALLEL_WORKERS=1
            echo "Applied level 2 degradation: disabled indexing, reduced workers"
            ;;
        3)
            export OML_READ_ONLY=true
            export PARALLEL_WORKERS=1
            echo "Applied level 3 degradation: read-only mode"
            ;;
    esac
}
```

---

## P1 重要优化（3-5 周）

### 4. 可观测性 ⭐⭐⭐⭐

#### 4.1 监控指标（Prometheus 格式）

**文件**: `~/.oml/core/session-metrics.py`

```python
#!/usr/bin/env python3
# Prometheus 格式指标导出

class MetricsCollector:
    def export_prometheus(self):
        return f"""
# HELP oml_sessions_total Total number of sessions
# TYPE oml_sessions_total gauge
oml_sessions_total{{type="active"}} {active_sessions}
oml_sessions_total{{type="total"}} {total_sessions}

# HELP oml_session_size_kb Average session size in KB
# TYPE oml_session_size_kb gauge
oml_session_size_kb {avg_size}

# HELP oml_operations_per_second Operations per second
# TYPE oml_operations_per_second gauge
oml_operations_per_second {ops_per_second}
"""
```

#### 4.2 告警规则

**文件**: `~/.oml/config/alerts.yaml`

```yaml
alerts:
  - name: high_session_count
    condition: "oml_sessions_total > 1000"
    severity: warning
    
  - name: high_error_rate
    condition: "oml_error_rate > 0.05"
    severity: warning
    
  - name: p99_latency_high
    condition: "oml_p99_latency_ms > 1000"
    severity: warning
```

---

### 5. 用户体验 ⭐⭐⭐⭐

#### 5.1 简化 CLI

```bash
# 新增：oml-session（简化版）
oml-session n [name]     # 创建新会话
oml-session l [filter]   # 列出会话
oml-session s <id>       # 显示详情
oml-session d <id>       # 删除会话
oml-session i            # 交互模式
oml-session h            # 帮助
```

#### 5.2 TUI 界面

**文件**: `~/.oml/core/session-tui.py`

```python
#!/usr/bin/env python3
# 基于 Textual 的终端 UI

from textual.app import App, ComposeResult
from textual.widgets import DataTable, Header, Footer
from textual.binding import Binding

class SessionTUI(App):
    BINDINGS = [
        Binding("q", "quit", "Quit"),
        Binding("r", "refresh", "Refresh"),
        Binding("d", "delete", "Delete"),
        Binding("enter", "show_detail", "Detail"),
    ]
    
    def compose(self) -> ComposeResult:
        yield Header()
        yield DataTable()
        yield Footer()
```

---

## P2 扩展优化（3 周）

### 6. 扩展性 ⭐⭐⭐

#### 6.1 插件化架构

**文件**: `~/.oml/core/plugin-manager.sh`

```bash
#!/usr/bin/env bash
# 插件管理器

PLUGIN_DIR="${OML_PLUGIN_DIR:-${HOME}/.oml/plugins}"

# 注册插件
register_plugin() {
    local plugin_path="$1"
    local name=$(basename "$plugin_path")
    
    mkdir -p "${PLUGIN_DIR}/${name}"
    cp -r "${plugin_path}"/* "${PLUGIN_DIR}/${name}/"
    
    echo "Plugin registered: $name"
}

# 加载插件
load_plugins() {
    for plugin_dir in "${PLUGIN_DIR}"/*/; do
        if [[ -f "${plugin_dir}main.sh" ]]; then
            source "${plugin_dir}main.sh"
            echo "Loaded plugin: $(basename "$plugin_dir")"
        fi
    done
}
```

#### 6.2 统一配置

**文件**: `~/.oml/config.yaml`

```yaml
session:
  storage:
    backend: file  # file | sqlite | redis
    directory: ~/.oml/sessions
    max_count: 1000
    ttl_days: 30
  
  encryption:
    enabled: true
    algorithm: aes-256-cbc

performance:
  parallel:
    enabled: true
    workers: auto
  
  cache:
    enabled: true
    size: 100
```

---

## 📅 实施路线图

### Phase 1（P0，2 周）
- [ ] 部署 `session-seal.sh`（加密）
- [ ] 部署 `session-audit.py`（审计）
- [ ] 部署 `retry-framework.sh`（重试）
- [ ] 部署 `session-rollback.sh`（回滚）

### Phase 2（P0，2 周）
- [ ] 部署 `session-parallel.sh`（并发）
- [ ] 部署 `context-lazy-loader.py`（懒加载）
- [ ] 部署 `degradation-strategies.sh`（降级）

### Phase 3（P1，3 周）
- [ ] 部署 `session-metrics.py`（监控）
- [ ] 部署 `session-alerts.yaml`（告警）
- [ ] 部署 `oml-session`（简化 CLI）
- [ ] 部署 `error-helpers.sh`（错误提示）

### Phase 4（P1，2 周）
- [ ] 部署 `session-tui.py`（TUI）
- [ ] 部署 `session-tracing.py`（追踪）

### Phase 5（P2，3 周）
- [ ] 部署 `plugin-manager.sh`（插件）
- [ ] 部署 `oml-config.yaml`（配置化）
- [ ] 重构为模块化架构

---

## ✅ 验收标准

| 类别 | 标准 | 验证方法 |
|------|------|----------|
| 安全性 | 所有数据加密存储 | 检查文件权限 |
| 安全性 | 审计日志可追溯 | 验证链哈希 |
| 性能 | 并发提升 3x+ | 基准测试 |
| 性能 | 懒加载减少 50% 内存 | 内存监控 |
| 容错 | 重试成功率>99% | 故障注入 |
| 容错 | 回滚时间<5 秒 | 计时测试 |
| 可观测 | 指标导出 Prometheus | Prometheus 验证 |
| 用户体验 | CLI 命令减少 50% | 命令数量对比 |

---

## 🔗 相关文档

- [会话管理](./SESSION-MANAGEMENT.md) - 会话生命周期
- [上下文优化](./CONTEXT-OPTIMIZATION.md) - 三层架构
- [实施清单](./IMPLEMENTATION-CHECKLIST.md) - 详细任务列表

---

*最后更新：2026-03-22 | 维护者：Oh My LiteCode Team*
