//! Times the Windows platform work GPUI does before an application callback
//! runs, piece by piece, so startup optimization targets the right stage.
//! Run with `cargo test --release -p gpuidart --lib startup_platform_costs
//! -- --ignored --nocapture`; the figures print as one JSON line.

use std::time::Instant;

use windows::Win32::Foundation::HMODULE;
use windows::Win32::Graphics::Direct3D::{
    D3D_DRIVER_TYPE_UNKNOWN, D3D_FEATURE_LEVEL_10_1, D3D_FEATURE_LEVEL_11_0, D3D_FEATURE_LEVEL_11_1,
};
use windows::Win32::Graphics::Direct3D11::{
    D3D11_CREATE_DEVICE_BGRA_SUPPORT, D3D11_SDK_VERSION, D3D11CreateDevice, ID3D11Device,
    ID3D11DeviceContext,
};
use windows::Win32::Graphics::DirectWrite::{
    DWRITE_FACTORY_TYPE_SHARED, DWriteCreateFactory, IDWriteFactory5,
};
use windows::Win32::Graphics::Dxgi::{
    CreateDXGIFactory2, DXGI_CREATE_FACTORY_FLAGS, IDXGIAdapter1, IDXGIFactory6,
};
use windows::core::Interface;

fn ms(since: Instant) -> f64 {
    since.elapsed().as_secs_f64() * 1000.0
}

#[test]
#[ignore = "timing probe for startup work; run explicitly"]
fn startup_platform_costs() {
    let started = Instant::now();
    let factory: IDWriteFactory5 =
        unsafe { DWriteCreateFactory(DWRITE_FACTORY_TYPE_SHARED) }.expect("DirectWrite factory");
    let directwrite_factory_ms = ms(started);

    // GPUI passes checkForUpdates = true; GPUIDART_PROBE_FONT_CHECK=0 times the
    // first enumeration in this process without it.
    let first_check = std::env::var("GPUIDART_PROBE_FONT_CHECK").as_deref() != Ok("0");
    let started = Instant::now();
    let mut checked = None;
    unsafe { factory.GetSystemFontCollection(false, &mut checked, first_check) }
        .expect("system font collection");
    let system_fonts_checked_ms = ms(started);

    let started = Instant::now();
    let mut cached = None;
    unsafe { factory.GetSystemFontCollection(false, &mut cached, false) }
        .expect("system font collection without update check");
    let system_fonts_cached_ms = ms(started);

    let started = Instant::now();
    let dxgi: IDXGIFactory6 =
        unsafe { CreateDXGIFactory2(DXGI_CREATE_FACTORY_FLAGS::default()) }.expect("DXGI factory");
    let adapter: IDXGIAdapter1 = unsafe { dxgi.EnumAdapters(0) }
        .expect("first adapter")
        .cast()
        .expect("adapter interface");
    let dxgi_factory_and_adapter_ms = ms(started);

    let started = Instant::now();
    let mut device: Option<ID3D11Device> = None;
    let mut context: Option<ID3D11DeviceContext> = None;
    unsafe {
        D3D11CreateDevice(
            &adapter,
            D3D_DRIVER_TYPE_UNKNOWN,
            HMODULE::default(),
            D3D11_CREATE_DEVICE_BGRA_SUPPORT,
            Some(&[
                D3D_FEATURE_LEVEL_11_1,
                D3D_FEATURE_LEVEL_11_0,
                D3D_FEATURE_LEVEL_10_1,
            ]),
            D3D11_SDK_VERSION,
            Some(&mut device),
            None,
            Some(&mut context),
        )
    }
    .expect("D3D11 device");
    let d3d11_device_ms = ms(started);

    let started = Instant::now();
    let application = gpui_kit::application();
    let application_ms = ms(started);
    drop(application);

    let started = Instant::now();
    let application = gpui_kit::application();
    let second_application_ms = ms(started);
    drop(application);

    println!(
        "{}",
        serde_json::json!({
            "directwrite_factory_ms": directwrite_factory_ms,
            "first_call_checks_for_updates": first_check,
            "system_fonts_first_call_ms": system_fonts_checked_ms,
            "system_fonts_cached_ms": system_fonts_cached_ms,
            "dxgi_factory_and_adapter_ms": dxgi_factory_and_adapter_ms,
            "d3d11_device_ms": d3d11_device_ms,
            "application_ms": application_ms,
            "second_application_ms": second_application_ms,
        })
    );
}
