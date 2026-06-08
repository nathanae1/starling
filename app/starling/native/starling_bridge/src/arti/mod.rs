//! Arti bridge — a C-compatible FFI surface around `arti-client` and
//! `tor-hsservice` for Starling's mobile app.
//!
//! Design:
//! - One opaque [`ArtiHandle`] owns a tokio runtime + a [`TorClient`] +
//!   an optional [`OnionService`] + a status snapshot.
//! - Every FFI call is wrapped in `catch_unwind` so we never unwind into
//!   Dart. Returned status codes are negative on error, zero on success.
//! - All long-running work (bootstrap, onion publish) runs on the runtime;
//!   FFI calls return immediately and progress is observable via
//!   [`arti_status`].
//!
//! See `native/starling_bridge/README.md` for build instructions and the
//! "Key decisions" section of the Plan 11a plan file for context.
//!
//! Lives at `crate::arti` in the merged starling_bridge crate. The FFI
//! entry points below are `#[no_mangle] pub extern "C"` so the C symbol
//! names (`arti_*`) are unchanged from the pre-merge layout.

use std::cell::RefCell;
use std::ffi::{c_char, c_int, CStr, CString};
use std::panic::{catch_unwind, AssertUnwindSafe};
use std::path::PathBuf;
use std::ptr;
use std::sync::Arc;

use parking_lot::{Mutex, RwLock};
use tokio::runtime::Runtime;

// The Tor core now lives in the shared `starling-arti` crate (consumed by
// both this FFI bridge and the headless relay). `ArtiNode` is the former
// local `Inner`; aliased so the rest of this shim is unchanged.
use starling_arti::{ArtiNode as Inner, InitMode, StatusSnapshot};

thread_local! {
    /// Most recent error message produced by an FFI call on this thread.
    /// Populated when an FFI returns NULL or a negative status; the caller
    /// can retrieve it via [`arti_last_error`] for richer diagnostics than
    /// the bare integer status code allows.
    static LAST_ERROR: RefCell<Option<String>> = const { RefCell::new(None) };
}

/// Process-wide handle slot. Survives Flutter hot restart (which destroys
/// the Dart isolate but leaves the native process alive). Tracks the
/// most recent live handle so a subsequent `arti_init` can tear the
/// orphan down before building a fresh one — without that, the second
/// init succeeds but `arti_create_onion_service` fails with "local
/// resource already in use" because `tor-hsservice` still holds an
/// exclusive lock on the nickname's on-disk state. Cleared by
/// [`arti_shutdown`].
static HANDLE_SLOT: Mutex<Option<usize>> = Mutex::new(None);

fn set_last_error(msg: impl Into<String>) {
    LAST_ERROR.with(|slot| *slot.borrow_mut() = Some(msg.into()));
}

fn clear_last_error() {
    LAST_ERROR.with(|slot| *slot.borrow_mut() = None);
}

// --- Status codes ---

pub const ARTI_OK: c_int = 0;
pub const ARTI_ERR_NULL: c_int = -1;
pub const ARTI_ERR_UTF8: c_int = -2;
pub const ARTI_ERR_PANIC: c_int = -3;
pub const ARTI_ERR_INIT: c_int = -4;
pub const ARTI_ERR_ONION: c_int = -5;
pub const ARTI_ERR_SHUTDOWN: c_int = -6;
pub const ARTI_ERR_BOOTSTRAP: c_int = -7;

/// Bootstrap mode passed to [`arti_init`].
/// - `0` — full bootstrap (synchronous; returns when ready). Foreground default.
/// - `1` — on-demand (returns immediately; circuits build lazily on first
///   stream, or eagerly via [`arti_bootstrap`]). iOS BGProcessingTask warm path.
pub const ARTI_BOOTSTRAP_FULL: u8 = 0;
pub const ARTI_BOOTSTRAP_ON_DEMAND: u8 = 1;

/// Status snapshot mirrored to Dart via an out-pointer. Layout MUST match
/// the FFI bindings in `lib/services/tor/ffi_bindings.dart`.
#[repr(C)]
pub struct ArtiStatus {
    pub bootstrap_percent: u32,
    pub circuit_count: u32,
    pub is_ready: bool,
    pub socks_port: u16,
}

/// Opaque handle. All FFI calls take `*mut ArtiHandle`.
pub struct ArtiHandle {
    runtime: Runtime,
    inner: Arc<RwLock<Inner>>,
}

// --- FFI surface ---

/// Initialize Arti and return an opaque handle.
///
/// `bootstrap_mode` selects how bootstrap proceeds:
///   - [`ARTI_BOOTSTRAP_FULL`] (`0`) — synchronous full bootstrap; this call
///     blocks until the client is ready for traffic. Foreground default.
///   - [`ARTI_BOOTSTRAP_ON_DEMAND`] (`1`) — returns immediately after the
///     client object is constructed; circuits are built lazily on first
///     stream, or eagerly via [`arti_bootstrap`]. Plan 14 Phase D warm path
///     for iOS BGProcessingTask.
///
/// `data_dir` must be a NUL-terminated UTF-8 path; Arti stores its state,
/// circuit cache, and onion-service keypair here.
///
/// On error returns NULL. The handle must be passed to [`arti_shutdown`]
/// to release resources.
#[no_mangle]
pub unsafe extern "C" fn arti_init(
    data_dir: *const c_char,
    bootstrap_mode: u8,
) -> *mut ArtiHandle {
    clear_last_error();
    let result = catch_unwind(AssertUnwindSafe(|| {
        // Hot-restart cleanup: if a prior Dart isolate left an Arti handle
        // alive in this process, tear it down before standing a new one
        // up. Otherwise `tor-hsservice`'s on-disk lock for our nickname
        // is still held and the new handle's `arti_create_onion_service`
        // fails with "local resource already in use".
        if let Some(addr) = HANDLE_SLOT.lock().take() {
            let prior = Box::from_raw(addr as *mut ArtiHandle);
            prior.runtime.block_on(async {
                let mut guard = prior.inner.write();
                guard.shutdown().await;
            });
            drop(prior);
        }
        if data_dir.is_null() {
            set_last_error("data_dir is NULL");
            return Err(ARTI_ERR_NULL);
        }
        let dir = match CStr::from_ptr(data_dir).to_str() {
            Ok(s) => PathBuf::from(s),
            Err(e) => {
                set_last_error(format!("data_dir is not valid UTF-8: {e}"));
                return Err(ARTI_ERR_UTF8);
            }
        };
        let runtime = match tokio::runtime::Builder::new_multi_thread()
            .worker_threads(2)
            .enable_all()
            .thread_name("arti-bridge")
            .build()
        {
            Ok(rt) => rt,
            Err(e) => {
                set_last_error(format!("build tokio runtime: {e}"));
                return Err(ARTI_ERR_INIT);
            }
        };
        let mode = match bootstrap_mode {
            ARTI_BOOTSTRAP_FULL => InitMode::Full,
            ARTI_BOOTSTRAP_ON_DEMAND => InitMode::OnDemand,
            other => {
                set_last_error(format!("unknown bootstrap_mode {other}"));
                return Err(ARTI_ERR_INIT);
            }
        };
        // `trust_permissions = true`: disable Arti's fs-mistrust check. The
        // mobile OS sandbox is the real boundary and inherited file modes
        // would otherwise trip the check. (The relay passes `false`.)
        let inner = match runtime.block_on(Inner::start(dir, mode, true)) {
            Ok(i) => Arc::new(RwLock::new(i)),
            Err(e) => {
                let msg = format!("arti_init failed: {e:?}");
                log::error!("{msg}");
                set_last_error(msg);
                return Err(ARTI_ERR_INIT);
            }
        };
        Ok(ArtiHandle { runtime, inner })
    }));
    match result {
        Ok(Ok(h)) => {
            let ptr = Box::into_raw(Box::new(h));
            *HANDLE_SLOT.lock() = Some(ptr as usize);
            ptr
        }
        Ok(Err(_)) => ptr::null_mut(),
        Err(_) => {
            set_last_error("arti_init panicked");
            ptr::null_mut()
        }
    }
}

/// Return a heap-allocated copy of the most recent error message produced
/// on this thread, or NULL if none has been recorded since the last clear.
/// The caller must free the returned string with [`arti_string_free`].
///
/// Errors are stored per-thread; call this from the same thread that
/// observed the failing FFI return.
#[no_mangle]
pub unsafe extern "C" fn arti_last_error() -> *mut c_char {
    let result = catch_unwind(AssertUnwindSafe(|| {
        LAST_ERROR.with(|slot| {
            slot.borrow()
                .as_ref()
                .and_then(|s| CString::new(s.as_str()).ok())
        })
    }));
    match result {
        Ok(Some(c)) => c.into_raw(),
        _ => ptr::null_mut(),
    }
}

/// Publish the on-device HTTP server (listening on `127.0.0.1:local_port`)
/// as a v3 onion service. Returns the `<address>.onion` host on success,
/// or NULL on error. The caller must free the returned string with
/// [`arti_string_free`].
///
/// The keypair lives under `<data_dir>/hs-state/<nickname>` so the address
/// is stable across restarts.
#[no_mangle]
pub unsafe extern "C" fn arti_create_onion_service(
    handle: *mut ArtiHandle,
    local_port: u16,
) -> *mut c_char {
    clear_last_error();
    let result = catch_unwind(AssertUnwindSafe(|| {
        if handle.is_null() {
            set_last_error("handle is NULL");
            return Err(ARTI_ERR_NULL);
        }
        let h = &*handle;
        let inner = h.inner.clone();
        let address = h
            .runtime
            .block_on(async move {
                let mut guard = inner.write();
                guard.create_onion_service(local_port).await
            })
            .map_err(|e| {
                let msg = format!("arti_create_onion_service failed: {e:?}");
                log::error!("{msg}");
                set_last_error(msg);
                ARTI_ERR_ONION
            })?;
        CString::new(address).map_err(|_| {
            set_last_error("onion address contained NUL byte");
            ARTI_ERR_UTF8
        })
    }));
    match result {
        Ok(Ok(c)) => c.into_raw(),
        Ok(Err(_)) => ptr::null_mut(),
        Err(_) => {
            set_last_error("arti_create_onion_service panicked");
            ptr::null_mut()
        }
    }
}

/// Drive bootstrap explicitly. Idempotent and safe to call multiple times;
/// concurrent calls coalesce on the in-flight attempt (per
/// `TorClient::bootstrap`). Useful with [`ARTI_BOOTSTRAP_ON_DEMAND`] when
/// the caller wants to ensure the client is ready before issuing requests
/// — bound the wait via a Dart-side timeout, not in Rust.
///
/// Returns [`ARTI_OK`] on success, [`ARTI_ERR_BOOTSTRAP`] on failure.
#[no_mangle]
pub unsafe extern "C" fn arti_bootstrap(handle: *mut ArtiHandle) -> c_int {
    clear_last_error();
    let result = catch_unwind(AssertUnwindSafe(|| {
        if handle.is_null() {
            set_last_error("handle is NULL");
            return ARTI_ERR_NULL;
        }
        let h = &*handle;
        let inner = h.inner.clone();
        let res = h.runtime.block_on(async move {
            let guard = inner.read();
            guard.bootstrap().await
        });
        match res {
            Ok(()) => ARTI_OK,
            Err(e) => {
                let msg = format!("arti_bootstrap failed: {e:?}");
                log::error!("{msg}");
                set_last_error(msg);
                ARTI_ERR_BOOTSTRAP
            }
        }
    }));
    result.unwrap_or(ARTI_ERR_PANIC)
}

/// Returns the local SOCKS5 port Arti uses for outbound connections, or 0
/// if the SOCKS proxy isn't running. Used by Plan 11b to route the Dart
/// `http.Client` through Tor.
#[no_mangle]
pub unsafe extern "C" fn arti_socks_port(handle: *mut ArtiHandle) -> u16 {
    let result = catch_unwind(AssertUnwindSafe(|| {
        if handle.is_null() {
            return 0u16;
        }
        let h = &*handle;
        h.inner.read().socks_port()
    }));
    result.unwrap_or(0)
}

/// Fill `out` with the latest status snapshot. Returns [`ARTI_OK`] or a
/// negative error code. `out` must point to a writable [`ArtiStatus`].
#[no_mangle]
pub unsafe extern "C" fn arti_status(
    handle: *mut ArtiHandle,
    out: *mut ArtiStatus,
) -> c_int {
    let result = catch_unwind(AssertUnwindSafe(|| {
        if handle.is_null() || out.is_null() {
            return ARTI_ERR_NULL;
        }
        let h = &*handle;
        let StatusSnapshot {
            bootstrap_percent,
            circuit_count,
            is_ready,
            socks_port,
        } = h.inner.read().status();
        ptr::write(
            out,
            ArtiStatus {
                bootstrap_percent,
                circuit_count,
                is_ready,
                socks_port,
            },
        );
        ARTI_OK
    }));
    result.unwrap_or(ARTI_ERR_PANIC)
}

/// Drop the handle, tear down the runtime, and unpublish the onion
/// service. After this call, `handle` MUST NOT be used again.
#[no_mangle]
pub unsafe extern "C" fn arti_shutdown(handle: *mut ArtiHandle) -> c_int {
    let result = catch_unwind(AssertUnwindSafe(|| {
        if handle.is_null() {
            return ARTI_ERR_NULL;
        }
        // Clear the singleton first so a concurrent `arti_init` doesn't
        // hand the same address back to a new caller mid-shutdown. Only
        // drop the box if it's the registered handle — otherwise we'd be
        // freeing memory still owned by the slot.
        {
            let mut slot = HANDLE_SLOT.lock();
            if matches!(*slot, Some(addr) if addr == handle as usize) {
                *slot = None;
            } else {
                return ARTI_OK;
            }
        }
        let boxed = Box::from_raw(handle);
        // Drop the inner state on the runtime so any pending tasks wind
        // down before the runtime itself is dropped.
        boxed.runtime.block_on(async {
            let mut guard = boxed.inner.write();
            guard.shutdown().await;
        });
        drop(boxed);
        ARTI_OK
    }));
    result.unwrap_or(ARTI_ERR_PANIC)
}

/// Free a string returned by [`arti_create_onion_service`].
#[no_mangle]
pub unsafe extern "C" fn arti_string_free(s: *mut c_char) {
    if s.is_null() {
        return;
    }
    let _ = catch_unwind(AssertUnwindSafe(|| {
        drop(CString::from_raw(s));
    }));
}
