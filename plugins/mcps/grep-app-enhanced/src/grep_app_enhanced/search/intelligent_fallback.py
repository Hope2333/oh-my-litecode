"""
Intelligent Fallback - 智能降级模块.

本模块提供多级降级策略和通路健康检查功能，支持：
- FallbackStrategy 类：多级降级逻辑
- 通路健康检查：实时监控通路状态
- 性能自适应调整：根据性能动态调整策略
- 错误恢复：自动重试和恢复机制

Example:
    ```python
    from grep_app_enhanced.search import FallbackStrategy

    strategy = FallbackStrategy()
    await strategy.initialize()

    # 执行带降级的搜索
    result = await strategy.execute_with_fallback(
        search_func,
        fallback_chain=["api", "clone", "crawler"]
    )
    ```

Fallback Levels:
    - Level 0: 首选通路（最快）
    - Level 1: 备用通路 1（中等速度）
    - Level 2: 备用通路 2（较慢）
    - Level 3: 最终回退（最慢但最可靠）

Health Check:
    - 通路可用性检测
    - 响应时间监控
    - 错误率统计
    - 速率限制追踪

Performance Adaptation:
    - 基于历史性能自动选择通路
    - 动态调整超时时间
    - 智能重试策略

Author:
    Oh My LiteCode Team
"""

from __future__ import annotations

import asyncio
import logging
import time
from dataclasses import dataclass, field
from enum import Enum
from typing import Any, Callable, Coroutine, Optional

logger = logging.getLogger(__name__)


class PathwayHealth(Enum):
    """通路健康状态枚举."""

    HEALTHY = "healthy"  # 健康
    DEGRADED = "degraded"  # 降级
    UNHEALTHY = "unhealthy"  # 不健康
    UNKNOWN = "unknown"  # 未知


class FallbackLevel(Enum):
    """降级级别枚举."""

    LEVEL_0 = 0  # 首选通路
    LEVEL_1 = 1  # 备用通路 1
    LEVEL_2 = 2  # 备用通路 2
    LEVEL_3 = 3  # 最终回退


@dataclass
class PathwayMetrics:
    """通路性能指标数据类.

    Attributes:
        pathway_id: 通路标识
        total_requests: 总请求数
        successful_requests: 成功请求数
        failed_requests: 失败请求数
        avg_response_time_ms: 平均响应时间（毫秒）
        p95_response_time_ms: P95 响应时间
        p99_response_time_ms: P99 响应时间
        error_rate: 错误率
        last_error: 最后错误信息
        last_success_time: 最后成功时间
        consecutive_failures: 连续失败次数
        rate_limit_remaining: 剩余请求数
        rate_limit_reset_at: 速率限制重置时间

    Example:
        ```python
        metrics = PathwayMetrics(pathway_id="api")
        print(f"错误率：{metrics.error_rate:.2%}")
        ```
    """

    pathway_id: str
    total_requests: int = 0
    successful_requests: int = 0
    failed_requests: int = 0
    avg_response_time_ms: float = 0.0
    p95_response_time_ms: float = 0.0
    p99_response_time_ms: float = 0.0
    error_rate: float = 0.0
    last_error: str = ""
    last_success_time: float = 0.0
    consecutive_failures: int = 0
    rate_limit_remaining: int = 1000
    rate_limit_reset_at: float = 0.0

    # 响应时间历史（用于计算百分位数）
    _response_times: list[float] = field(default_factory=list, repr=False)

    def record_success(self, response_time_ms: float) -> None:
        """记录成功请求.

        Args:
            response_time_ms: 响应时间（毫秒）
        """
        self.total_requests += 1
        self.successful_requests += 1
        self.consecutive_failures = 0
        self.last_success_time = time.time()

        self._response_times.append(response_time_ms)
        self._update_stats()

    def record_failure(self, error: str) -> None:
        """记录失败请求.

        Args:
            error: 错误信息
        """
        self.total_requests += 1
        self.failed_requests += 1
        self.consecutive_failures += 1
        self.last_error = error

        self._update_stats()

    def _update_stats(self) -> None:
        """更新统计数据."""
        # 更新错误率
        if self.total_requests > 0:
            self.error_rate = self.failed_requests / self.total_requests

        # 更新平均响应时间
        if self._response_times:
            self.avg_response_time_ms = sum(self._response_times) / len(
                self._response_times
            )

            # 计算百分位数
            sorted_times = sorted(self._response_times)
            p95_idx = int(len(sorted_times) * 0.95)
            p99_idx = int(len(sorted_times) * 0.99)
            self.p95_response_time_ms = (
                sorted_times[p95_idx] if p95_idx < len(sorted_times) else 0
            )
            self.p99_response_time_ms = (
                sorted_times[p99_idx] if p99_idx < len(sorted_times) else 0
            )

        # 限制历史记录大小
        if len(self._response_times) > 1000:
            self._response_times = self._response_times[-1000:]

    def get_health(self) -> PathwayHealth:
        """获取通路健康状态.

        Returns:
            健康状态
        """
        # 检查速率限制
        if self.rate_limit_remaining < 10:
            return PathwayHealth.DEGRADED

        # 检查连续失败
        if self.consecutive_failures >= 5:
            return PathwayHealth.UNHEALTHY

        # 检查错误率
        if self.error_rate > 0.5:
            return PathwayHealth.UNHEALTHY
        elif self.error_rate > 0.2:
            return PathwayHealth.DEGRADED

        # 检查响应时间
        if self.avg_response_time_ms > 5000:  # > 5 秒
            return PathwayHealth.DEGRADED

        # 检查是否有成功记录
        if self.last_success_time == 0:
            return PathwayHealth.UNKNOWN

        return PathwayHealth.HEALTHY

    def to_dict(self) -> dict[str, Any]:
        """转换为字典格式."""
        return {
            "pathway_id": self.pathway_id,
            "total_requests": self.total_requests,
            "successful_requests": self.successful_requests,
            "failed_requests": self.failed_requests,
            "success_rate": round(1 - self.error_rate, 4),
            "error_rate": round(self.error_rate, 4),
            "avg_response_time_ms": round(self.avg_response_time_ms, 2),
            "p95_response_time_ms": round(self.p95_response_time_ms, 2),
            "p99_response_time_ms": round(self.p99_response_time_ms, 2),
            "consecutive_failures": self.consecutive_failures,
            "rate_limit_remaining": self.rate_limit_remaining,
            "health": self.get_health().value,
            "last_error": self.last_error,
        }


@dataclass
class FallbackConfig:
    """降级配置数据类.

    Attributes:
        max_retries: 最大重试次数
        retry_delay_ms: 重试延迟（毫秒）
        exponential_backoff: 是否使用指数退避
        timeout_ms: 超时时间（毫秒）
        circuit_breaker_threshold: 熔断器阈值（连续失败次数）
        circuit_breaker_timeout_ms: 熔断器超时时间（毫秒）
        health_check_interval_ms: 健康检查间隔（毫秒）
        enable_adaptive_timeout: 启用自适应超时
        enable_circuit_breaker: 启用熔断器

    Example:
        ```python
        config = FallbackConfig(
            max_retries=3,
            timeout_ms=10000,
            enable_circuit_breaker=True
        )
        ```
    """

    max_retries: int = 3
    retry_delay_ms: int = 100
    exponential_backoff: bool = True
    timeout_ms: int = 10000
    circuit_breaker_threshold: int = 5
    circuit_breaker_timeout_ms: int = 30000
    health_check_interval_ms: int = 5000
    enable_adaptive_timeout: bool = True
    enable_circuit_breaker: bool = True


@dataclass
class FallbackResult:
    """降级执行结果数据类.

    Attributes:
        success: 是否成功
        result: 执行结果
        pathway_used: 使用的通路
        fallback_level: 降级级别
        attempts: 尝试次数
        total_time_ms: 总耗时（毫秒）
        error: 错误信息（如果失败）
        fallback_chain: 降级链路

    Example:
        ```python
        result = FallbackResult(
            success=True,
            result=data,
            pathway_used="api",
            total_time_ms=150.5
        )
        ```
    """

    success: bool
    result: Any = None
    pathway_used: str = ""
    fallback_level: FallbackLevel = FallbackLevel.LEVEL_0
    attempts: int = 0
    total_time_ms: float = 0.0
    error: str | None = None
    fallback_chain: list[str] = field(default_factory=list)

    def to_dict(self) -> dict[str, Any]:
        """转换为字典格式."""
        return {
            "success": self.success,
            "pathway_used": self.pathway_used,
            "fallback_level": self.fallback_level.value,
            "attempts": self.attempts,
            "total_time_ms": round(self.total_time_ms, 2),
            "error": self.error,
            "fallback_chain": self.fallback_chain,
        }


class CircuitBreaker:
    """熔断器实现.

    当通路连续失败达到阈值时，自动熔断该通路，
    在超时后尝试半开状态，成功则恢复.

    Attributes:
        failure_threshold: 失败阈值
        timeout_ms: 超时时间（毫秒）
    """

    def __init__(
        self,
        failure_threshold: int = 5,
        timeout_ms: int = 30000,
    ) -> None:
        """初始化熔断器.

        Args:
            failure_threshold: 失败阈值
            timeout_ms: 超时时间（毫秒）
        """
        self.failure_threshold = failure_threshold
        self.timeout_ms = timeout_ms

        self._failure_count = 0
        self._last_failure_time: float = 0
        self._state = "closed"  # closed, open, half-open

    @property
    def state(self) -> str:
        """获取当前状态."""
        if self._state == "open":
            # 检查是否应该切换到半开状态
            if time.time() * 1000 - self._last_failure_time >= self.timeout_ms:
                self._state = "half-open"
        return self._state

    def record_success(self) -> None:
        """记录成功."""
        self._failure_count = 0
        self._state = "closed"

    def record_failure(self) -> None:
        """记录失败."""
        self._failure_count += 1
        self._last_failure_time = time.time() * 1000

        if self._failure_count >= self.failure_threshold:
            self._state = "open"
            logger.warning(f"熔断器打开：连续失败 {self._failure_count} 次")

    def can_execute(self) -> bool:
        """检查是否可以执行.

        Returns:
            如果可以执行返回 True
        """
        state = self.state
        if state == "closed":
            return True
        elif state == "half-open":
            return True
        else:  # open
            return False


class FallbackStrategy:
    """智能降级策略类.

    提供多级降级逻辑、通路健康检查、性能自适应调整和错误恢复功能.

    Attributes:
        config: 降级配置
        default_fallback_chain: 默认降级链路

    Example:
        ```python
        strategy = FallbackStrategy(
            max_retries=3,
            timeout_ms=10000
        )
        await strategy.initialize()

        async def search_api():
            return await api_search()

        async def search_clone():
            return await clone_search()

        result = await strategy.execute_with_fallback(
            search_api,
            fallback_chain=[search_api, search_clone]
        )
        ```

    Note:
        - 支持自动重试和指数退避
        - 支持熔断器模式
        - 支持性能自适应调整
        - 完整的健康检查机制
    """

    def __init__(
        self,
        config: FallbackConfig | None = None,
        default_fallback_chain: list[str] | None = None,
    ) -> None:
        """初始化降级策略.

        Args:
            config: 降级配置
            default_fallback_chain: 默认降级链路
        """
        self.config = config or FallbackConfig()
        self.default_fallback_chain = default_fallback_chain or [
            "api",
            "clone",
            "crawler",
            "http_fallback",
        ]

        # 通路指标
        self._metrics: dict[str, PathwayMetrics] = {}

        # 熔断器
        self._circuit_breakers: dict[str, CircuitBreaker] = {}

        # 初始化指标
        for pathway_id in self.default_fallback_chain:
            self._metrics[pathway_id] = PathwayMetrics(pathway_id=pathway_id)
            self._circuit_breakers[pathway_id] = CircuitBreaker(
                failure_threshold=self.config.circuit_breaker_threshold,
                timeout_ms=self.config.circuit_breaker_timeout_ms,
            )

        # 后台任务
        self._health_check_task: Optional[asyncio.Task] = None
        self._running = False

        # 性能基准
        self._performance_benchmark: dict[str, list[float]] = {
            p: [] for p in self.default_fallback_chain
        }

    async def initialize(self) -> None:
        """初始化降级策略."""
        self._running = True

        # 启动健康检查任务
        if self.config.health_check_interval_ms > 0:
            self._health_check_task = asyncio.create_task(
                self._health_check_loop()
            )

        logger.info("FallbackStrategy 初始化完成")

    async def close(self) -> None:
        """关闭降级策略."""
        self._running = False

        if self._health_check_task:
            self._health_check_task.cancel()
            try:
                await self._health_check_task
            except asyncio.CancelledError:
                pass

        logger.info("FallbackStrategy 已关闭")

    async def __aenter__(self) -> FallbackStrategy:
        """异步上下文管理器入口."""
        await self.initialize()
        return self

    async def __aexit__(self, exc_type: Any, exc_val: Any, exc_tb: Any) -> None:
        """异步上下文管理器出口."""
        await self.close()

    def get_metrics(self, pathway_id: str) -> PathwayMetrics | None:
        """获取通路指标.

        Args:
            pathway_id: 通路标识

        Returns:
            通路指标
        """
        return self._metrics.get(pathway_id)

    def get_all_metrics(self) -> dict[str, dict[str, Any]]:
        """获取所有通路指标.

        Returns:
            通路指标字典
        """
        return {
            pathway_id: metrics.to_dict()
            for pathway_id, metrics in self._metrics.items()
        }

    def get_healthy_pathways(self) -> list[str]:
        """获取健康通路列表.

        Returns:
            健康通路标识列表
        """
        healthy = []
        for pathway_id, metrics in self._metrics.items():
            if metrics.get_health() != PathwayHealth.UNHEALTHY:
                cb = self._circuit_breakers.get(pathway_id)
                if cb and cb.can_execute():
                    healthy.append(pathway_id)
        return healthy

    def get_best_pathway(self) -> str:
        """获取最佳通路.

        基于历史性能选择响应时间最短的健康通路.

        Returns:
            最佳通路标识
        """
        healthy_pathways = self.get_healthy_pathways()

        if not healthy_pathways:
            # 所有通路都不健康，返回默认
            return self.default_fallback_chain[0]

        # 选择平均响应时间最短的通路
        best_pathway = healthy_pathways[0]
        best_time = float("inf")

        for pathway_id in healthy_pathways:
            metrics = self._metrics[pathway_id]
            if metrics.avg_response_time_ms < best_time:
                best_time = metrics.avg_response_time_ms
                best_pathway = pathway_id

        return best_pathway

    def _calculate_adaptive_timeout(self, pathway_id: str) -> int:
        """计算自适应超时时间.

        基于历史响应时间的 P95 计算超时时间.

        Args:
            pathway_id: 通路标识

        Returns:
            超时时间（毫秒）
        """
        if not self.config.enable_adaptive_timeout:
            return self.config.timeout_ms

        metrics = self._metrics.get(pathway_id)
        if not metrics or metrics.p95_response_time_ms == 0:
            return self.config.timeout_ms

        # P95 * 2 作为超时时间，最小 1 秒，最大 60 秒
        timeout = int(metrics.p95_response_time_ms * 2)
        return max(1000, min(60000, timeout))

    async def _health_check_loop(self) -> None:
        """健康检查循环."""
        while self._running:
            try:
                await asyncio.sleep(self.config.health_check_interval_ms / 1000)

                # 检查所有通路健康状态
                for pathway_id, metrics in self._metrics.items():
                    health = metrics.get_health()
                    if health == PathwayHealth.UNHEALTHY:
                        logger.warning(f"通路不健康：{pathway_id}")
                    elif health == PathwayHealth.DEGRADED:
                        logger.debug(f"通路降级：{pathway_id}")

            except asyncio.CancelledError:
                break
            except Exception as e:
                logger.error(f"健康检查失败：{e}")

    async def execute_with_fallback(
        self,
        primary_func: Callable[[], Coroutine[Any, Any, Any]],
        fallback_chain: list[Callable[[], Coroutine[Any, Any, Any]]] | None = None,
        pathway_id: str = "primary",
        max_retries: int | None = None,
    ) -> FallbackResult:
        """执行带降级的函数调用.

        Args:
            primary_func: 主函数
            fallback_chain: 降级函数链
            pathway_id: 通路标识
            max_retries: 最大重试次数

        Returns:
            降级执行结果

        Example:
            ```python
            async def api_search():
                return await api.search()

            async def clone_search():
                return await clone.search()

            result = await strategy.execute_with_fallback(
                api_search,
                fallback_chain=[clone_search],
                pathway_id="api"
            )
            ```
        """
        start_time = time.perf_counter()
        fallback_chain = fallback_chain or []
        max_retries = max_retries if max_retries is not None else self.config.max_retries

        # 初始化通路指标
        if pathway_id not in self._metrics:
            self._metrics[pathway_id] = PathwayMetrics(pathway_id=pathway_id)
            self._circuit_breakers[pathway_id] = CircuitBreaker(
                failure_threshold=self.config.circuit_breaker_threshold,
                timeout_ms=self.config.circuit_breaker_timeout_ms,
            )

        metrics = self._metrics[pathway_id]
        circuit_breaker = self._circuit_breakers[pathway_id]

        # 检查熔断器
        if self.config.enable_circuit_breaker and not circuit_breaker.can_execute():
            logger.warning(f"通路 {pathway_id} 熔断中，执行降级")
            return await self._execute_fallback_chain(
                fallback_chain, start_time, pathway_id
            )

        # 计算超时时间
        timeout = self._calculate_adaptive_timeout(pathway_id)

        # 执行主函数（带重试）
        last_error = ""
        for attempt in range(max_retries + 1):
            try:
                result = await asyncio.wait_for(primary_func(), timeout=timeout / 1000)

                # 记录成功
                elapsed = (time.perf_counter() - start_time) * 1000
                metrics.record_success(elapsed)
                circuit_breaker.record_success()

                # 更新性能基准
                self._performance_benchmark.setdefault(pathway_id, []).append(elapsed)
                if len(self._performance_benchmark[pathway_id]) > 100:
                    self._performance_benchmark[pathway_id] = self._performance_benchmark[pathway_id][-100:]

                return FallbackResult(
                    success=True,
                    result=result,
                    pathway_used=pathway_id,
                    fallback_level=FallbackLevel.LEVEL_0,
                    attempts=attempt + 1,
                    total_time_ms=elapsed,
                )

            except asyncio.TimeoutError as e:
                last_error = f"超时 ({timeout}ms)"
                logger.warning(f"通路 {pathway_id} 超时：{last_error}")
                metrics.record_failure(last_error)
                circuit_breaker.record_failure()

            except Exception as e:
                last_error = str(e)
                logger.warning(f"通路 {pathway_id} 失败：{last_error}")
                metrics.record_failure(last_error)
                circuit_breaker.record_failure()

            # 重试延迟（指数退避）
            if attempt < max_retries:
                delay = self._calculate_retry_delay(attempt)
                logger.debug(f"重试延迟 {delay}ms")
                await asyncio.sleep(delay / 1000)

        # 主函数失败，执行降级链
        logger.info(f"主通路失败，执行降级链：{pathway_id}")
        return await self._execute_fallback_chain(
            fallback_chain, start_time, pathway_id, last_error
        )

    def _calculate_retry_delay(self, attempt: int) -> int:
        """计算重试延迟.

        使用指数退避策略.

        Args:
            attempt: 当前尝试次数

        Returns:
            延迟时间（毫秒）
        """
        if not self.config.exponential_backoff:
            return self.config.retry_delay_ms

        # 指数退避：delay * 2^attempt
        return self.config.retry_delay_ms * (2 ** attempt)

    async def _execute_fallback_chain(
        self,
        fallback_chain: list[Callable[[], Coroutine[Any, Any, Any]]],
        start_time: float,
        primary_pathway: str,
        last_error: str = "",
    ) -> FallbackResult:
        """执行降级链.

        Args:
            fallback_chain: 降级函数链
            start_time: 开始时间
            primary_pathway: 主通路标识
            last_error: 最后错误信息

        Returns:
            降级执行结果
        """
        fallback_chain_used = [primary_pathway]

        for level, fallback_func in enumerate(fallback_chain, 1):
            pathway_id = f"fallback_{level}"

            # 初始化通路指标
            if pathway_id not in self._metrics:
                self._metrics[pathway_id] = PathwayMetrics(pathway_id=pathway_id)
                self._circuit_breakers[pathway_id] = CircuitBreaker(
                    failure_threshold=self.config.circuit_breaker_threshold,
                    timeout_ms=self.config.circuit_breaker_timeout_ms,
                )

            metrics = self._metrics[pathway_id]
            circuit_breaker = self._circuit_breakers[pathway_id]

            # 检查熔断器
            if self.config.enable_circuit_breaker and not circuit_breaker.can_execute():
                logger.debug(f"降级通路 {pathway_id} 熔断中，跳过")
                continue

            # 计算超时时间
            timeout = self._calculate_adaptive_timeout(pathway_id)
            fallback_chain_used.append(pathway_id)

            try:
                result = await asyncio.wait_for(
                    fallback_func(), timeout=timeout / 1000
                )

                # 记录成功
                elapsed = (time.perf_counter() - start_time) * 1000
                metrics.record_success(elapsed)
                circuit_breaker.record_success()

                return FallbackResult(
                    success=True,
                    result=result,
                    pathway_used=pathway_id,
                    fallback_level=FallbackLevel(level),
                    attempts=level + 1,
                    total_time_ms=elapsed,
                    fallback_chain=fallback_chain_used,
                )

            except asyncio.TimeoutError as e:
                error_msg = f"降级超时 ({timeout}ms)"
                logger.warning(f"降级通路 {pathway_id} 超时")
                metrics.record_failure(error_msg)
                circuit_breaker.record_failure()

            except Exception as e:
                error_msg = str(e)
                logger.warning(f"降级通路 {pathway_id} 失败：{error_msg}")
                metrics.record_failure(error_msg)
                circuit_breaker.record_failure()

        # 所有降级都失败
        total_time = (time.perf_counter() - start_time) * 1000
        return FallbackResult(
            success=False,
            pathway_used="",
            fallback_level=FallbackLevel.LEVEL_3,
            attempts=len(fallback_chain) + 1,
            total_time_ms=total_time,
            error=last_error or "所有通路都失败",
            fallback_chain=fallback_chain_used,
        )

    async def recover_pathway(self, pathway_id: str) -> bool:
        """尝试恢复通路.

        重置通路的熔断器和失败计数.

        Args:
            pathway_id: 通路标识

        Returns:
            是否恢复成功
        """
        if pathway_id not in self._metrics:
            return False

        metrics = self._metrics[pathway_id]
        circuit_breaker = self._circuit_breakers.get(pathway_id)

        # 重置熔断器
        if circuit_breaker:
            circuit_breaker._failure_count = 0
            circuit_breaker._state = "half-open"

        # 重置连续失败计数
        metrics.consecutive_failures = 0

        logger.info(f"尝试恢复通路：{pathway_id}")
        return True

    def get_performance_report(self) -> dict[str, Any]:
        """获取性能报告.

        Returns:
            性能报告字典
        """
        report = {
            "pathways": {},
            "best_pathway": self.get_best_pathway(),
            "healthy_pathways": self.get_healthy_pathways(),
            "timestamp": time.time(),
        }

        for pathway_id, metrics in self._metrics.items():
            report["pathways"][pathway_id] = metrics.to_dict()

        return report


# 预定义的降级策略配置
DEFAULT_FALLBACK_CONFIG = FallbackConfig(
    max_retries=3,
    retry_delay_ms=100,
    timeout_ms=10000,
    circuit_breaker_threshold=5,
    circuit_breaker_timeout_ms=30000,
    health_check_interval_ms=5000,
    enable_adaptive_timeout=True,
    enable_circuit_breaker=True,
)

FAST_FALLBACK_CONFIG = FallbackConfig(
    max_retries=1,
    retry_delay_ms=50,
    timeout_ms=5000,
    circuit_breaker_threshold=3,
    circuit_breaker_timeout_ms=15000,
    health_check_interval_ms=2000,
    enable_adaptive_timeout=True,
    enable_circuit_breaker=True,
)

RELIABLE_FALLBACK_CONFIG = FallbackConfig(
    max_retries=5,
    retry_delay_ms=200,
    timeout_ms=30000,
    circuit_breaker_threshold=10,
    circuit_breaker_timeout_ms=60000,
    health_check_interval_ms=10000,
    enable_adaptive_timeout=True,
    enable_circuit_breaker=True,
)
