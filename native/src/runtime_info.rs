use serde_json::{Value, json};

pub(crate) fn read() -> Value {
    #[allow(unused_mut)]
    let mut value = json!({"pid": std::process::id(), "os": std::env::consts::OS, "arch": std::env::consts::ARCH});
    #[cfg(unix)]
    unsafe {
        let mut usage: libc::rusage = std::mem::zeroed();
        if libc::getrusage(libc::RUSAGE_SELF, &mut usage) == 0 {
            value["cpu_user_us"] =
                json!(usage.ru_utime.tv_sec * 1_000_000 + i64::from(usage.ru_utime.tv_usec));
            value["cpu_system_us"] =
                json!(usage.ru_stime.tv_sec * 1_000_000 + i64::from(usage.ru_stime.tv_usec));
        }
    }
    #[cfg(target_os = "linux")]
    {
        match std::fs::read_to_string("/proc/self/maps") {
            Ok(maps) => {
                let libraries: std::collections::BTreeSet<_> = maps
                    .lines()
                    .filter(|line| {
                        line.split_whitespace()
                            .nth(1)
                            .is_some_and(|flags| flags.contains('x'))
                    })
                    .filter_map(|line| line.find('/').map(|start| &line[start..]))
                    .collect();
                value["loaded_images"] = json!(libraries);
                value["loaded_images_source"] = json!("/proc/self/maps executable file mappings");
            }
            Err(error) => value["loaded_images_error"] = json!(error.to_string()),
        }
        match std::fs::read_to_string("/proc/self/smaps_rollup") {
            Ok(smaps) => {
                let mut memory = serde_json::Map::new();
                for line in smaps.lines() {
                    let mut parts = line.split_whitespace();
                    if let (Some(key), Some(amount), Some("kB")) =
                        (parts.next(), parts.next(), parts.next())
                        && let Ok(amount) = amount.parse::<u64>()
                    {
                        memory.insert(key.trim_end_matches(':').to_owned(), json!(amount * 1024));
                    }
                }
                value["memory_bytes"] = json!(memory);
                value["memory_source"] = json!(
                    "/proc/self/smaps_rollup; RSS includes shared pages; PSS apportions them"
                );
            }
            Err(error) => value["memory_error"] = json!(error.to_string()),
        }
        value["main_thread"] = json!(unsafe { libc::gettid() == libc::getpid() });
    }
    #[cfg(target_os = "macos")]
    unsafe {
        let mut libraries = std::collections::BTreeSet::new();
        for i in 0..libc::_dyld_image_count() {
            let name = libc::_dyld_get_image_name(i);
            if !name.is_null() {
                libraries.insert(
                    std::ffi::CStr::from_ptr(name)
                        .to_string_lossy()
                        .into_owned(),
                );
            }
        }
        value["loaded_images"] = json!(libraries);
        value["loaded_images_source"] = json!("dyld image enumeration");
        let mut usage: libc::rusage_info_v0 = std::mem::zeroed();
        if libc::proc_pid_rusage(
            libc::getpid(),
            libc::RUSAGE_INFO_V0,
            (&mut usage as *mut libc::rusage_info_v0).cast(),
        ) == 0
        {
            value["memory_bytes"] = json!({"resident_size": usage.ri_resident_size, "physical_footprint": usage.ri_phys_footprint});
            value["memory_source"] = json!(
                "proc_pid_rusage RUSAGE_INFO_V0; resident size and physical footprint are separate OS metrics"
            );
        } else {
            value["memory_error"] = json!(std::io::Error::last_os_error().to_string());
        }
        value["main_thread"] = json!(libc::pthread_main_np() == 1);
    }
    value
}

/// Optional diagnostics extension, version 1. Read-only process metadata.
#[unsafe(no_mangle)]
pub extern "C" fn gd_runtime_version() -> u32 {
    1
}

/// `length` must be writable. Free the returned allocation with gd_free_event.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn gd_runtime_read(length: *mut usize) -> *mut u8 {
    if length.is_null() {
        return std::ptr::null_mut();
    }
    unsafe {
        *length = 0;
    }
    crate::boundary::call(std::ptr::null_mut(), || {
        let Ok(bytes) = serde_json::to_vec(&read()) else {
            return std::ptr::null_mut();
        };
        let bytes = bytes.into_boxed_slice();
        unsafe {
            *length = bytes.len();
        }
        Box::into_raw(bytes).cast()
    })
}

#[cfg(all(test, unix))]
mod tests {
    #[test]
    fn runtime_probe_reports_current_process_loaded_images_and_memory() {
        let value = super::read();
        assert_eq!(value["pid"], std::process::id());
        assert!(
            value["loaded_images"]
                .as_array()
                .is_some_and(|images| !images.is_empty())
        );
        assert!(
            value["memory_bytes"]
                .as_object()
                .is_some_and(|memory| !memory.is_empty())
        );
        assert!(value["cpu_user_us"].as_i64().is_some_and(|time| time >= 0));
        assert!(value.get("loaded_images_error").is_none());
        assert!(value.get("memory_error").is_none());
    }
}
