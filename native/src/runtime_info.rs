use serde_json::{Value, json};

pub(crate) fn read() -> Value {
    #[cfg(all(feature = "allocation-profile", not(test)))]
    let heap = crate::heap_profile::snapshot();
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
            #[cfg(target_os = "linux")]
            {
                value["memory_peak_bytes"] = json!({"rss": usage.ru_maxrss * 1024});
                value["memory_peak_source"] = json!(
                    "getrusage RUSAGE_SELF ru_maxrss; lifetime high-water RSS, KiB converted to bytes"
                );
            }
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
        let mut usage: libc::rusage_info_v4 = std::mem::zeroed();
        if libc::proc_pid_rusage(
            libc::getpid(),
            libc::RUSAGE_INFO_V4,
            (&mut usage as *mut libc::rusage_info_v4).cast(),
        ) == 0
        {
            value["memory_bytes"] = json!({"resident_size": usage.ri_resident_size, "physical_footprint": usage.ri_phys_footprint});
            value["memory_peak_bytes"] =
                json!({"physical_footprint": usage.ri_lifetime_max_phys_footprint});
            value["memory_peak_source"] =
                json!("proc_pid_rusage RUSAGE_INFO_V4 lifetime maximum physical footprint");
            value["memory_source"] = json!(
                "proc_pid_rusage RUSAGE_INFO_V4; resident size and physical footprint are separate OS metrics"
            );
        } else {
            value["memory_error"] = json!(std::io::Error::last_os_error().to_string());
        }
        value["main_thread"] = json!(libc::pthread_main_np() == 1);
    }
    #[cfg(windows)]
    windows::append(&mut value);
    #[cfg(all(feature = "allocation-profile", not(test)))]
    {
        value["rust_allocator"] = heap;
    }
    value
}

#[cfg(windows)]
mod windows {
    use super::*;
    use std::ffi::c_void;

    #[repr(C)]
    #[derive(Default)]
    struct FileTime {
        low: u32,
        high: u32,
    }
    impl FileTime {
        fn micros(&self) -> u64 {
            ((u64::from(self.high) << 32) | u64::from(self.low)) / 10
        }
    }
    #[repr(C)]
    #[derive(Default)]
    struct MemoryCounters {
        size: u32,
        page_fault_count: u32,
        peak_working_set: usize,
        working_set: usize,
        quota_peak_paged: usize,
        quota_paged: usize,
        quota_peak_nonpaged: usize,
        quota_nonpaged: usize,
        pagefile: usize,
        peak_pagefile: usize,
        private_usage: usize,
    }
    #[link(name = "kernel32")]
    unsafe extern "system" {
        fn GetCurrentProcess() -> *mut c_void;
        fn GetProcessTimes(
            process: *mut c_void,
            creation: *mut FileTime,
            exit: *mut FileTime,
            kernel: *mut FileTime,
            user: *mut FileTime,
        ) -> i32;
    }
    #[repr(C)]
    struct ModuleInfo {
        base: *mut c_void,
        size_of_image: u32,
        entry: *mut c_void,
    }
    #[link(name = "psapi")]
    unsafe extern "system" {
        fn GetProcessMemoryInfo(
            process: *mut c_void,
            counters: *mut MemoryCounters,
            size: u32,
        ) -> i32;
        fn EnumProcessModulesEx(
            process: *mut c_void,
            modules: *mut *mut c_void,
            size: u32,
            needed: *mut u32,
            filter: u32,
        ) -> i32;
        fn GetModuleFileNameExW(
            process: *mut c_void,
            module: *mut c_void,
            name: *mut u16,
            size: u32,
        ) -> u32;
        fn GetModuleInformation(
            process: *mut c_void,
            module: *mut c_void,
            info: *mut ModuleInfo,
            size: u32,
        ) -> i32;
        fn QueryWorkingSet(process: *mut c_void, buffer: *mut c_void, size: u32) -> i32;
    }

    struct Image {
        path: String,
        base: usize,
        size_of_image: Option<u32>,
        resident_bytes: usize,
        resident_shared_bytes: usize,
    }

    /// The resident pages of the process, attributed to the image whose
    /// mapping holds each page: a working-set walk (`QueryWorkingSet`) lists
    /// every page in memory with its shared flag, and a page inside an
    /// image's range counts toward that image. Pages outside every image
    /// are heap, stacks and other mappings.
    fn working_set(process: *mut c_void, images: &mut [Image]) -> Result<Value, String> {
        const ERROR_BAD_LENGTH: i32 = 24;
        const PAGE: usize = 4096;
        let mut buffer: Vec<usize> = vec![0; 1 << 16];
        loop {
            let bytes = (buffer.len() * std::mem::size_of::<usize>()) as u32;
            if unsafe { QueryWorkingSet(process, buffer.as_mut_ptr().cast(), bytes) } != 0 {
                break;
            }
            let error = std::io::Error::last_os_error();
            // On a short buffer the first entry holds the count required.
            if error.raw_os_error() == Some(ERROR_BAD_LENGTH) && buffer.len() < 1 << 24 {
                let needed = buffer[0].saturating_add(1 << 12).max(buffer.len() * 2);
                buffer = vec![0; needed];
                continue;
            }
            return Err(error.to_string());
        }
        let count = buffer[0].min(buffer.len() - 1);
        let mut ranges: Vec<(usize, usize, usize)> = images
            .iter()
            .enumerate()
            .filter_map(|(index, image)| {
                image
                    .size_of_image
                    .map(|size| (image.base, image.base + size as usize, index))
            })
            .collect();
        ranges.sort_unstable();
        let (mut total, mut shared, mut in_images) = (0usize, 0usize, 0usize);
        for &block in &buffer[1..=count] {
            let address = (block >> 12) << 12;
            let is_shared = block & (1 << 8) != 0;
            total += PAGE;
            if is_shared {
                shared += PAGE;
            }
            let candidate = ranges.partition_point(|(base, _, _)| *base <= address);
            if let Some(&(_, end, index)) = candidate.checked_sub(1).map(|at| &ranges[at]) {
                if address < end {
                    in_images += PAGE;
                    images[index].resident_bytes += PAGE;
                    if is_shared {
                        images[index].resident_shared_bytes += PAGE;
                    }
                }
            }
        }
        Ok(json!({
            "resident_bytes": total,
            "shared_bytes": shared,
            "private_bytes": total - shared,
            "in_images_bytes": in_images,
            "outside_images_bytes": total - in_images,
            "pages": count,
        }))
    }

    /// Every image mapped into the process with its size and base, so a
    /// memory floor can be attributed to the libraries behind it.
    fn loaded_images(process: *mut c_void) -> Result<Vec<Image>, String> {
        const LIST_MODULES_ALL: u32 = 0x03;
        let mut handles: Vec<*mut c_void> = vec![std::ptr::null_mut(); 2048];
        let mut needed = 0u32;
        let capacity = (handles.len() * std::mem::size_of::<*mut c_void>()) as u32;
        if unsafe {
            EnumProcessModulesEx(
                process,
                handles.as_mut_ptr(),
                capacity,
                &mut needed,
                LIST_MODULES_ALL,
            )
        } == 0
        {
            return Err("EnumProcessModulesEx failed".into());
        }
        let count = (needed as usize / std::mem::size_of::<*mut c_void>()).min(handles.len());
        let mut images = Vec::with_capacity(count);
        for &module in &handles[..count] {
            let mut name = [0u16; 1024];
            let length = unsafe {
                GetModuleFileNameExW(process, module, name.as_mut_ptr(), name.len() as u32)
            };
            let path = String::from_utf16_lossy(&name[..length as usize]);
            let mut info = ModuleInfo {
                base: std::ptr::null_mut(),
                size_of_image: 0,
                entry: std::ptr::null_mut(),
            };
            let size = if unsafe {
                GetModuleInformation(
                    process,
                    module,
                    &mut info,
                    std::mem::size_of::<ModuleInfo>() as u32,
                )
            } != 0
            {
                Some(info.size_of_image)
            } else {
                None
            };
            images.push(Image {
                path,
                base: info.base as usize,
                size_of_image: size,
                resident_bytes: 0,
                resident_shared_bytes: 0,
            });
        }
        Ok(images)
    }

    pub(super) fn append(value: &mut Value) {
        let process = unsafe { GetCurrentProcess() };
        match loaded_images(process) {
            Ok(mut images) => {
                match working_set(process, &mut images) {
                    Ok(pages) => {
                        value["working_set_pages"] = pages;
                        value["working_set_pages_source"] = json!(
                            "QueryWorkingSet; each resident page attributed to the image whose mapping holds it, shared by the OS flag"
                        );
                    }
                    Err(error) => value["working_set_pages_error"] = json!(error),
                }
                // Largest resident share first, mapped size second.
                images.sort_by_key(|image| {
                    std::cmp::Reverse((image.resident_bytes, image.size_of_image.unwrap_or(0)))
                });
                value["loaded_images_total_bytes"] = json!(
                    images
                        .iter()
                        .map(|image| u64::from(image.size_of_image.unwrap_or(0)))
                        .sum::<u64>()
                );
                value["loaded_images"] = json!(
                    images
                        .iter()
                        .map(|image| {
                            json!({
                                "path": image.path,
                                "size_of_image": image.size_of_image,
                                "resident_bytes": image.resident_bytes,
                                "resident_shared_bytes": image.resident_shared_bytes,
                            })
                        })
                        .collect::<Vec<_>>()
                );
                value["loaded_images_source"] = json!(
                    "EnumProcessModulesEx with GetModuleInformation SizeOfImage and the working-set walk's resident pages"
                );
            }
            Err(error) => value["loaded_images_error"] = json!(error),
        }
        let mut memory = MemoryCounters {
            size: std::mem::size_of::<MemoryCounters>() as u32,
            ..Default::default()
        };
        if unsafe { GetProcessMemoryInfo(process, &mut memory, memory.size) } != 0 {
            value["memory_bytes"] =
                json!({"working_set": memory.working_set, "private_commit": memory.private_usage});
            value["memory_peak_bytes"] =
                json!({"working_set": memory.peak_working_set, "commit": memory.peak_pagefile});
            value["memory_source"] = json!(
                "GetProcessMemoryInfo PROCESS_MEMORY_COUNTERS_EX; working set and private commit are separate OS metrics"
            );
            value["memory_peak_source"] = json!(
                "PROCESS_MEMORY_COUNTERS_EX PeakWorkingSetSize and PeakPagefileUsage; lifetime high-water marks"
            );
        } else {
            value["memory_error"] = json!(std::io::Error::last_os_error().to_string());
        }
        let (mut creation, mut exit, mut kernel, mut user) = (
            FileTime::default(),
            FileTime::default(),
            FileTime::default(),
            FileTime::default(),
        );
        if unsafe { GetProcessTimes(process, &mut creation, &mut exit, &mut kernel, &mut user) }
            != 0
        {
            value["cpu_user_us"] = json!(user.micros());
            value["cpu_system_us"] = json!(kernel.micros());
        } else {
            value["cpu_error"] = json!(std::io::Error::last_os_error().to_string());
        }
    }
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

#[cfg(test)]
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
        #[cfg(windows)]
        {
            assert!(value.get("working_set_pages_error").is_none());
            let pages = &value["working_set_pages"];
            assert!(
                pages["resident_bytes"]
                    .as_u64()
                    .is_some_and(|bytes| bytes > 0)
            );
            assert!(
                pages["in_images_bytes"].as_u64().unwrap()
                    <= pages["resident_bytes"].as_u64().unwrap()
            );
            let resident: u64 = value["loaded_images"]
                .as_array()
                .unwrap()
                .iter()
                .map(|image| image["resident_bytes"].as_u64().unwrap())
                .sum();
            assert_eq!(resident, pages["in_images_bytes"].as_u64().unwrap());
            assert!(resident > 0, "the test binary itself has resident pages");
        }
        assert!(
            value["memory_peak_bytes"]
                .as_object()
                .is_some_and(|memory| !memory.is_empty())
        );
        assert!(value.get("cpu_error").is_none());
    }
}
