//! One Rust archive owns all engines, including the existing OCR C ABI.
pub use ocrus_ffi::*;
use serde::Deserialize;
use std::ffi::{CStr, CString, c_char};
use std::panic::{AssertUnwindSafe, catch_unwind};
use std::sync::{
    Arc, Mutex, OnceLock,
    atomic::{AtomicBool, Ordering},
};
#[cfg(test)]
use std::time::Duration;

static USAGE_BUSY: AtomicBool = AtomicBool::new(false);
static MARKDOWN_BUSY: AtomicBool = AtomicBool::new(false);
static RUNTIME: OnceLock<tokio::runtime::Runtime> = OnceLock::new();

#[derive(Deserialize)]
#[serde(deny_unknown_fields)]
struct Request {
    #[serde(default)]
    refresh: bool,
    url: Option<String>,
}
struct State {
    cancelled: AtomicBool,
    markdown_cancel: get_md::embedding::Cancellation,
    result: Mutex<Option<String>>,
    taken: AtomicBool,
}
pub struct IgniteroJob {
    state: Arc<State>,
}
struct BusyGuard(&'static AtomicBool);
impl Drop for BusyGuard {
    fn drop(&mut self) {
        self.0.store(false, Ordering::Release);
    }
}

fn cancelled(state: &State) -> bool {
    state.cancelled.load(Ordering::Relaxed)
}
fn execute(kind: u32, request: Request, state: &State) -> Result<serde_json::Value, String> {
    if cancelled(state) {
        return Err("処理を中止しました。".into());
    }
    if kind == 1 {
        let runtime = if let Some(runtime) = RUNTIME.get() {
            runtime
        } else {
            let candidate = tokio::runtime::Builder::new_multi_thread()
                .worker_threads(4)
                .enable_all()
                .build()
                .map_err(|e| e.to_string())?;
            let _ = RUNTIME.set(candidate);
            RUNTIME
                .get()
                .ok_or("利用枠の取得を開始できませんでした。")?
        };
        // Do not drop collection mid-refresh/cache write on user cancellation.
        // The provider/lock deadlines remain owned by ai-usage; retain busy until
        // collection has finished, then discard a cancelled result.
        runtime.block_on(finish_collection(state, async {
            ai_usage::embedding::collect(ai_usage::embedding::CollectOptions {
                refresh: request.refresh,
                ..Default::default()
            })
            .await
            .map_err(|e| format!("{e:#}"))
            .and_then(|v| serde_json::to_value(v).map_err(|e| e.to_string()))
        }))
    } else {
        let options = get_md::embedding::FetchOptions::new(request.url.ok_or("URLがありません。")?);
        let document = get_md::embedding::fetch(options, &state.markdown_cancel)
            .map_err(|e| format!("{e:#}"))?;
        if document.markdown.len() > 2 * 1024 * 1024 {
            return Err("ページが大きすぎます。別のURLを指定してください。".into());
        }
        serde_json::to_value(document).map_err(|e| e.to_string())
    }
}

async fn finish_collection<T>(
    state: &State,
    work: impl std::future::Future<Output = Result<T, String>>,
) -> Result<T, String> {
    let result = work.await?;
    if cancelled(state) {
        return Err("処理を中止しました。".into());
    }
    Ok(result)
}

fn message(text: String) -> *mut c_char {
    CString::new(text.replace('\0', "�"))
        .expect("NUL removed")
        .into_raw()
}

/// # Safety
/// Pointers must follow the ownership and validity contract in ignitero_tools.h.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn ignitero_job_start(
    kind: u32,
    request: *const c_char,
    out_status: *mut i32,
    out_error: *mut *mut c_char,
) -> *mut IgniteroJob {
    if out_error.is_null() || out_status.is_null() {
        return std::ptr::null_mut();
    }
    unsafe {
        *out_error = std::ptr::null_mut();
        *out_status = 1;
    }
    let result = catch_unwind(AssertUnwindSafe(|| -> Result<*mut IgniteroJob, String> {
        if request.is_null() {
            return Err("要求がありません。".into());
        }
        let text = unsafe { CStr::from_ptr(request) }
            .to_str()
            .map_err(|_| "要求の文字コードが不正です。")?;
        if text.len() > 16_384 {
            return Err("要求が長すぎます。".into());
        }
        let request: Request = serde_json::from_str(text).map_err(|_| "要求の形式が不正です。")?;
        let busy = match kind {
            1 => &USAGE_BUSY,
            2 => &MARKDOWN_BUSY,
            _ => return Err("未対応の処理です。".into()),
        };
        if kind == 2 && request.url.is_none() {
            return Err("URLがありません。".into());
        }
        if busy
            .compare_exchange(false, true, Ordering::AcqRel, Ordering::Acquire)
            .is_err()
        {
            unsafe {
                *out_status = 2;
            }
            return Err("前の処理を終了しています。少し待ってからもう一度お試しください。".into());
        }
        let guard = BusyGuard(busy);
        let state = Arc::new(State {
            cancelled: AtomicBool::new(false),
            markdown_cancel: Default::default(),
            result: Mutex::new(None),
            taken: AtomicBool::new(false),
        });
        let worker = state.clone();
        std::thread::Builder::new()
            .name(format!("ignitero-tool-{kind}"))
            .spawn(move || {
                let _guard = guard;
                let result = catch_unwind(AssertUnwindSafe(|| execute(kind, request, &worker)))
                    .unwrap_or_else(|_| {
                        Err("処理中にエラーが発生しました。もう一度お試しください。".into())
                    });
                let envelope = match result {
                    Ok(data) => serde_json::json!({"schema_version":1,"data":data}),
                    Err(error) => serde_json::json!({"schema_version":1,"error":error}),
                };
                *worker
                    .result
                    .lock()
                    .unwrap_or_else(std::sync::PoisonError::into_inner) =
                    Some(envelope.to_string());
            })
            .map_err(|e| e.to_string())?;
        Ok(Box::into_raw(Box::new(IgniteroJob { state })))
    }));
    match result {
        Ok(Ok(job)) => {
            unsafe {
                *out_status = 0;
            }
            job
        }
        Ok(Err(error)) => {
            unsafe {
                *out_error = message(error);
            }
            std::ptr::null_mut()
        }
        Err(_) => {
            unsafe {
                *out_error = message("処理を開始できませんでした。".into());
            }
            std::ptr::null_mut()
        }
    }
}

/// # Safety
/// job must be live, out_json writable, and polling serialized.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn ignitero_job_poll(
    job: *mut IgniteroJob,
    out_json: *mut *mut c_char,
) -> i32 {
    if job.is_null() || out_json.is_null() {
        return -1;
    }
    unsafe {
        *out_json = std::ptr::null_mut();
    }
    catch_unwind(AssertUnwindSafe(|| {
        let state = unsafe { &(*job).state };
        if state.taken.load(Ordering::Relaxed) {
            return -1;
        }
        let mut result = state
            .result
            .lock()
            .unwrap_or_else(std::sync::PoisonError::into_inner);
        if let Some(text) = result.take() {
            state.taken.store(true, Ordering::Relaxed);
            unsafe {
                *out_json = message(text);
            }
            1
        } else {
            0
        }
    }))
    .unwrap_or(-1)
}
/// # Safety
/// job must be live until this call returns (NULL is accepted).
#[unsafe(no_mangle)]
pub unsafe extern "C" fn ignitero_job_cancel(job: *mut IgniteroJob) {
    if let Some(job) = unsafe { job.as_ref() } {
        job.state.cancelled.store(true, Ordering::Relaxed);
        job.state.markdown_cancel.cancel();
    }
}
/// # Safety
/// Free one owned handle once, after all calls using it have returned.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn ignitero_job_free(job: *mut IgniteroJob) {
    if !job.is_null() {
        unsafe {
            ignitero_job_cancel(job);
            drop(Box::from_raw(job));
        }
    }
}
/// # Safety
/// value must be NULL or a live string returned by this ABI, freed exactly once.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn ignitero_string_free(value: *mut c_char) {
    if !value.is_null() {
        unsafe {
            drop(CString::from_raw(value));
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    fn shared_usage_fixture_preserves_missing_and_zero_percentages() {
        let value: serde_json::Value = serde_json::from_str(include_str!(
            "../../../Tests/IgniteroCoreTests/Fixtures/EmbeddedTools.json"
        ))
        .unwrap();
        assert_eq!(value["schema_version"], 1);
        let report: ai_usage::report::Report =
            serde_json::from_value(value["data"]["report"].clone()).unwrap();
        let roundtrip = serde_json::to_value(report).unwrap();
        assert_eq!(roundtrip["accounts"][0]["five_hour"]["used_percent"], 0.0);
        assert!(roundtrip["accounts"][0]["weekly"]["used_percent"].is_null());
        assert_eq!(roundtrip["accounts"][1]["ok"], false);
    }
    #[test]
    fn worker_errors_are_structured_and_results_are_taken_once() {
        let request = CString::new(r#"{"url":"file:///tmp/page"}"#).unwrap();
        let mut error = std::ptr::null_mut();
        let job = unsafe { ignitero_job_start(2, request.as_ptr(), &mut 0, &mut error) };
        assert!(!job.is_null());
        let deadline = std::time::Instant::now() + Duration::from_secs(5);
        let mut output = std::ptr::null_mut();
        while unsafe { ignitero_job_poll(job, &mut output) } == 0 {
            assert!(std::time::Instant::now() < deadline);
            std::thread::sleep(Duration::from_millis(5));
        }
        let value: serde_json::Value =
            serde_json::from_str(unsafe { CStr::from_ptr(output) }.to_str().unwrap()).unwrap();
        assert_eq!(value["schema_version"], 1);
        assert!(value["error"].as_str().unwrap().contains("HTTP"));
        unsafe {
            ignitero_string_free(output);
            assert_eq!(ignitero_job_poll(job, &mut output), -1);
            assert!(output.is_null());
            ignitero_job_cancel(job);
            ignitero_job_free(job);
        }
    }
    #[test]
    fn cancellation_finishes_collection_before_releasing_its_result() {
        let runtime = tokio::runtime::Builder::new_current_thread()
            .enable_all()
            .build()
            .unwrap();
        let state = State {
            cancelled: AtomicBool::new(false),
            markdown_cancel: Default::default(),
            result: Mutex::new(None),
            taken: AtomicBool::new(false),
        };
        let finished = AtomicBool::new(false);
        runtime.block_on(async {
            let (send, receive) = tokio::sync::oneshot::channel::<()>();
            let work = async {
                receive.await.unwrap();
                finished.store(true, Ordering::Relaxed);
                Ok(())
            };
            let stop = async {
                state.cancelled.store(true, Ordering::Relaxed);
                send.send(()).unwrap();
            };
            let (result, _) = tokio::join!(finish_collection(&state, work), stop);
            assert!(result.is_err());
            assert!(finished.load(Ordering::Relaxed));
        });
    }
    #[test]
    fn busy_has_a_distinct_start_status() {
        assert!(!USAGE_BUSY.swap(true, Ordering::AcqRel));
        let _guard = BusyGuard(&USAGE_BUSY);
        let request = CString::new("{}").unwrap();
        let mut status = 0;
        let mut error = std::ptr::null_mut();
        let job = unsafe { ignitero_job_start(1, request.as_ptr(), &mut status, &mut error) };
        assert!(job.is_null());
        assert_eq!(status, 2);
        unsafe {
            ignitero_string_free(error);
        }
    }
    #[test]
    fn invalid_request_never_starts_a_worker() {
        for (kind, text) in [
            (9, "{}"),
            (1, "invalid"),
            (2, "{}"),
            (1, "{\"unexpected\":true}"),
        ] {
            let text = CString::new(text).unwrap();
            let mut error = std::ptr::null_mut();
            let job = unsafe { ignitero_job_start(kind, text.as_ptr(), &mut 0, &mut error) };
            assert!(job.is_null());
            assert!(!error.is_null());
            unsafe {
                ignitero_string_free(error);
            }
        }
    }
}

/// Whether a previous worker of this kind is still releasing its resources.
#[unsafe(no_mangle)]
pub extern "C" fn ignitero_job_busy(kind: u32) -> i32 {
    match kind {
        1 => i32::from(USAGE_BUSY.load(Ordering::Acquire)),
        2 => i32::from(MARKDOWN_BUSY.load(Ordering::Acquire)),
        _ => -1,
    }
}
