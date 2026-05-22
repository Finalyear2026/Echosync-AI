// EchoSync AI Desktop — Tauri shell
// Manages sidecar lifecycle, health-check polling, graceful shutdown, and crash restart.

use std::time::Duration;
use std::sync::Mutex;
use tauri::{AppHandle, Emitter, RunEvent, Manager};
use tauri_plugin_shell::ShellExt;
use tauri_plugin_shell::process::CommandChild;

const HEALTH_URL: &str = "http://127.0.0.1:8765/health";
const SHUTDOWN_URL: &str = "http://127.0.0.1:8765/shutdown";
const MAX_RESTART_ATTEMPTS: u32 = 3;
const RESTART_DELAY_MS: u64 = 2000;
const HEALTH_POLL_INTERVAL_MS: u64 = 500;
const HEALTH_TIMEOUT_SECS: u64 = 10;

pub struct SidecarState(pub Mutex<Option<CommandChild>>);

#[cfg_attr(mobile, tauri::mobile_entry_point)]
pub fn run() {
    tauri::Builder::default()
        .plugin(tauri_plugin_shell::init())
        .plugin(tauri_plugin_notification::init())
        .manage(SidecarState(Mutex::new(None)))
        .setup(|app| {
            let handle = app.handle().clone();
            tauri::async_runtime::spawn(async move {
                manage_sidecar(handle).await;
            });
            Ok(())
        })
        .build(tauri::generate_context!())
        .expect("error while building tauri application")
        .run(|app_handle, event| {
            if let RunEvent::ExitRequested { .. } = event {
                let state = app_handle.state::<SidecarState>();
                tauri::async_runtime::block_on(async {
                    shutdown_sidecar(&state).await;
                });
            }
        });
}

/// Top-level sidecar manager — spawns and restarts up to MAX_RESTART_ATTEMPTS times.
async fn manage_sidecar(handle: AppHandle) {
    for attempt in 0..MAX_RESTART_ATTEMPTS {
        if attempt > 0 {
            tokio::time::sleep(Duration::from_millis(RESTART_DELAY_MS)).await;
            eprintln!(
                "EchoSync: restarting sidecar (attempt {}/{}).",
                attempt + 1,
                MAX_RESTART_ATTEMPTS
            );
        }

        match spawn_sidecar(&handle).await {
            Ok(ready) => {
                if ready {
                    eprintln!("EchoSync: sidecar ready.");
                    let _ = handle.emit("sidecar-ready", ());
                    return;
                }
                eprintln!("EchoSync: sidecar health check timed out.");
            }
            Err(e) => {
                eprintln!("EchoSync: sidecar spawn error: {}", e);
            }
        }
    }

    eprintln!(
        "EchoSync: sidecar failed after {} attempts.",
        MAX_RESTART_ATTEMPTS
    );
    let _ = handle.emit("sidecar-error", "Sidecar failed to start.");
}

/// Spawn the sidecar binary and wait for /health to respond.
/// Returns Ok(true) if healthy, Ok(false) on timeout, Err on spawn failure.
async fn spawn_sidecar(handle: &AppHandle) -> Result<bool, String> {
    // In dev mode, the sidecar is started manually — just wait for health
    #[cfg(dev)]
    {
        eprintln!("EchoSync: dev mode — waiting for manually started sidecar...");
        // In dev mode, we don't spawn the process, so we don't store a handle
        return Ok(wait_for_health().await);
    }

    #[cfg(not(dev))]
    {
        match handle.shell().sidecar("echosync-sidecar") {
            Err(e) => {
                eprintln!("EchoSync: sidecar binary not found: {}", e);
                eprintln!("EchoSync: falling back to manually started sidecar...");
                return Ok(wait_for_health().await);
            }
            Ok(cmd) => {
                eprintln!("EchoSync: spawning sidecar process...");
                let child = cmd.spawn().map_err(|e| {
                    eprintln!("EchoSync: failed to spawn sidecar: {}", e);
                    e.to_string()
                })?;
                
                // Store the child handle for clean shutdown
                let state = handle.state::<SidecarState>();
                if let Ok(mut guard) = state.0.lock() {
                    *guard = Some(child);
                    eprintln!("EchoSync: sidecar process handle stored for clean shutdown.");
                } else {
                    eprintln!("EchoSync: warning - failed to store sidecar handle!");
                }
                
                Ok(wait_for_health().await)
            }
        }
    }
}

/// Poll GET /health every 500ms until 200 OK or 10-second timeout.
async fn wait_for_health() -> bool {
    let client = match reqwest::Client::builder()
        .timeout(Duration::from_secs(2))
        .build()
    {
        Ok(c) => c,
        Err(_) => return false,
    };

    let deadline =
        tokio::time::Instant::now() + Duration::from_secs(HEALTH_TIMEOUT_SECS);

    while tokio::time::Instant::now() < deadline {
        if let Ok(resp) = client.get(HEALTH_URL).send().await {
            if resp.status().is_success() {
                return true;
            }
        }
        tokio::time::sleep(Duration::from_millis(HEALTH_POLL_INTERVAL_MS)).await;
    }
    false
}

/// POST /shutdown and wait up to 5 seconds for graceful exit, then kill if still running.
async fn shutdown_sidecar(state: &SidecarState) {
    eprintln!("EchoSync: initiating sidecar shutdown...");
    
    // First, try graceful shutdown via HTTP
    let client = match reqwest::Client::builder()
        .timeout(Duration::from_secs(3))
        .build()
    {
        Ok(c) => c,
        Err(e) => {
            eprintln!("EchoSync: failed to create HTTP client: {}", e);
            // Skip HTTP shutdown, go straight to kill
            force_kill_sidecar(state).await;
            return;
        }
    };
    
    match client.post(SHUTDOWN_URL).send().await {
        Ok(resp) => {
            eprintln!("EchoSync: shutdown request sent (status: {})", resp.status());
        }
        Err(e) => {
            eprintln!("EchoSync: shutdown request failed: {}", e);
        }
    }
    
    // Wait for graceful shutdown
    tokio::time::sleep(Duration::from_millis(1500)).await;

    // Force kill if still running
    force_kill_sidecar(state).await;
}

/// Force kill the sidecar process if it's still running.
async fn force_kill_sidecar(state: &SidecarState) {
    if let Ok(mut guard) = state.0.lock() {
        if let Some(mut child) = guard.take() {
            eprintln!("EchoSync: force-killing sidecar process...");
            match child.kill() {
                Ok(_) => {
                    eprintln!("EchoSync: sidecar process killed successfully.");
                }
                Err(e) => {
                    eprintln!("EchoSync: failed to kill sidecar process: {}", e);
                }
            }
        } else {
            eprintln!("EchoSync: no sidecar process handle to kill (dev mode or manual start).");
        }
    } else {
        eprintln!("EchoSync: failed to acquire lock on sidecar state.");
    }
}
