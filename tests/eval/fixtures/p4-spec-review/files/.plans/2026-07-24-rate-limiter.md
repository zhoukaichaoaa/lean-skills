# Plan: per-key rate limiter

Goal: throttle the public API per API key, in process, no external services.

## Requirements

R1. `RateLimiter(limit, window_seconds)` - a fixed-window counter keyed by a
    caller-supplied string.

R2. `allow(key)` returns True while the key is under `limit` within the current
    window, and False once it has reached the limit.

R3. The window resets: once `window_seconds` have elapsed since the window
    opened for a key, that key's count starts again at zero.

R4. `remaining(key)` returns how many calls the key has left in its current
    window.

R5. A key never seen before is allowed and opens a fresh window.

## Out of scope

- Persistence of any kind. In-memory only, lost on restart.
- Logging. The caller decides what to log.
- Distributed / multi-process coordination.
