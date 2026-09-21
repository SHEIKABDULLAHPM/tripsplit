/// Fixed-window in-memory rate limiter keyed by client IP.
///
/// Stale entries are evicted periodically to prevent unbounded memory growth.
/// A production deployment would front this with a shared store (e.g.
/// Cloudflare or the host's reverse proxy).
library;

/// Sliding-fixed-window limiter for one route group.
class RateLimiter {
  RateLimiter({
    required int maxRequests,
    this.windowMs = const Duration(minutes: 1),
    this.ttlMs = const Duration(minutes: 5),
  }) : _max = maxRequests;

  final int _max;
  final Duration windowMs;
  final Duration ttlMs;
  final Map<String, _Window> _windows = {};

  /// Returns true when a request from [key] is still allowed.
  bool allow(String key, {int nowMs = 0}) {
    final now = nowMs == 0 ? DateTime.now().millisecondsSinceEpoch : nowMs;
    _evictStale(now);
    final window = _windows.putIfAbsent(key, () => _Window());
    if (now - window.startedAt >= windowMs.inMilliseconds) {
      window.startedAt = now;
      window.count = 0;
    }
    window.count += 1;
    return window.count <= _max;
  }

  /// Removes windows that have not been touched within [ttlMs].
  void _evictStale(int nowMs) {
    if (_windows.isEmpty) return;
    if (_evictionCounter++ % 128 != 0) return;
    _windows.removeWhere((_, w) => nowMs - w.startedAt > ttlMs.inMilliseconds);
  }

  int _evictionCounter = 0;
}

class _Window {
  int startedAt = DateTime.now().millisecondsSinceEpoch;
  int count = 0;
}
