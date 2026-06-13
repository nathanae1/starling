//! Token-bucket rate limiting (D6). One [`RateLimiter`] guards one router
//! instance — client identity is meaningless behind onion services (every
//! request arrives from Arti on loopback), so the correct granularity is
//! per-router (= per Owner endpoint, or per admin surface), not per-IP.

use std::sync::{Arc, Mutex};
use std::time::Instant;

use axum::extract::{Request, State};
use axum::http::{header, StatusCode};
use axum::middleware::Next;
use axum::response::{IntoResponse, Response};

#[derive(Clone)]
pub struct RateLimiter {
    inner: Arc<Mutex<Bucket>>,
}

struct Bucket {
    tokens: f64,
    capacity: f64,
    refill_per_sec: f64,
    last: Instant,
}

impl RateLimiter {
    /// `rate` requests per minute sustained, with up to `burst` immediately
    /// available.
    pub fn per_minute(rate: u32, burst: u32) -> Self {
        RateLimiter {
            inner: Arc::new(Mutex::new(Bucket {
                tokens: burst as f64,
                capacity: burst as f64,
                refill_per_sec: rate as f64 / 60.0,
                last: Instant::now(),
            })),
        }
    }

    /// Take one token, or return the whole seconds until one is available.
    pub fn try_acquire(&self) -> Result<(), u64> {
        self.try_acquire_at(Instant::now())
    }

    fn try_acquire_at(&self, now: Instant) -> Result<(), u64> {
        let mut b = self.inner.lock().expect("rate limiter lock");
        let elapsed = now.duration_since(b.last).as_secs_f64();
        b.tokens = (b.tokens + elapsed * b.refill_per_sec).min(b.capacity);
        b.last = now;
        if b.tokens >= 1.0 {
            b.tokens -= 1.0;
            Ok(())
        } else {
            Err(((1.0 - b.tokens) / b.refill_per_sec).ceil() as u64)
        }
    }
}

/// Axum middleware: 429 + `Retry-After` when the bucket is dry.
pub async fn rate_limit_mw(
    State(limiter): State<RateLimiter>,
    req: Request,
    next: Next,
) -> Response {
    match limiter.try_acquire() {
        Ok(()) => next.run(req).await,
        Err(retry_after) => (
            StatusCode::TOO_MANY_REQUESTS,
            [(header::RETRY_AFTER, retry_after.to_string())],
            "rate limited",
        )
            .into_response(),
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::time::Duration;

    #[test]
    fn burst_drains_then_refills() {
        let l = RateLimiter::per_minute(60, 3); // 1/sec, burst 3
        let t0 = Instant::now();
        assert!(l.try_acquire_at(t0).is_ok());
        assert!(l.try_acquire_at(t0).is_ok());
        assert!(l.try_acquire_at(t0).is_ok());
        // Bucket dry: a full token is 1s away.
        assert_eq!(l.try_acquire_at(t0), Err(1));
        // After 1s one token has refilled.
        assert!(l.try_acquire_at(t0 + Duration::from_secs(1)).is_ok());
        assert_eq!(l.try_acquire_at(t0 + Duration::from_secs(1)), Err(1));
    }

    #[test]
    fn refill_caps_at_burst() {
        let l = RateLimiter::per_minute(600, 2); // 10/sec, burst 2
        let t0 = Instant::now();
        assert!(l.try_acquire_at(t0).is_ok());
        assert!(l.try_acquire_at(t0).is_ok());
        // A long idle stretch must not bank more than `burst` tokens.
        let later = t0 + Duration::from_secs(3600);
        assert!(l.try_acquire_at(later).is_ok());
        assert!(l.try_acquire_at(later).is_ok());
        assert!(l.try_acquire_at(later).is_err());
    }

    #[test]
    fn retry_after_reflects_deficit() {
        let l = RateLimiter::per_minute(6, 1); // 0.1/sec → 10s per token
        let t0 = Instant::now();
        assert!(l.try_acquire_at(t0).is_ok());
        assert_eq!(l.try_acquire_at(t0), Err(10));
    }
}
