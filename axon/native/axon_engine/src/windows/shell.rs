#[cfg(target_os = "windows")]
use windows::{
    core::PCWSTR,
    Win32::{
        Foundation::{CloseHandle, HANDLE, HWND},
        System::Threading::{WaitForSingleObject, INFINITE},
        UI::Shell::{
            ShellExecuteExW, SEE_MASK_NOCLOSEPROCESS, SHELLEXECUTEINFOW,
        },
        UI::WindowsAndMessaging::SW_HIDE,
    },
};
use std::ffi::OsStr;
use std::os::windows::ffi::OsStrExt;

pub fn run_privileged_command(command: &str, parameters: &str) -> Result<(), String> {
    #[cfg(target_os = "windows")]
    unsafe {
        run_privileged_command_impl(command, parameters)
    }
    #[cfg(not(target_os = "windows"))]
    Err("ShellExecute unavailable on non-Windows OS".to_string())
}

#[cfg(target_os = "windows")]
unsafe fn run_privileged_command_impl(command: &str, parameters: &str) -> Result<(), String> {
    let verb = to_pcwstr("runas");
    let file = to_pcwstr(command);
    let params = to_pcwstr(parameters);

    let mut info = SHELLEXECUTEINFOW {
        cbSize: std::mem::size_of::<SHELLEXECUTEINFOW>() as u32,
        fMask: SEE_MASK_NOCLOSEPROCESS,
        hwnd: HWND(0),
        lpVerb: PCWSTR(verb.as_ptr()),
        lpFile: PCWSTR(file.as_ptr()),
        lpParameters: PCWSTR(params.as_ptr()),
        lpDirectory: PCWSTR::null(),
        nShow: SW_HIDE.0 as i32,
        hInstApp: windows::Win32::Foundation::HINSTANCE(0),
        lpIDList: std::ptr::null_mut(),
        lpClass: PCWSTR::null(),
        hkeyClass: windows::Win32::System::Registry::HKEY(0),
        dwHotKey: 0,
        Anonymous: windows::Win32::UI::Shell::SHELLEXECUTEINFOW_0 { hMonitor: HANDLE(0) },
        hProcess: HANDLE(0),
    };

    let result = ShellExecuteExW(&mut info);

    if result.is_ok() {
        if info.hProcess.is_invalid() == false {
            WaitForSingleObject(info.hProcess, INFINITE);
            let _ = CloseHandle(info.hProcess);
            Ok(())
        } else {
            // Process finished immediately or handle not returned, but execution started successfully
            Ok(())
        }
    } else {
        Err("ShellExecuteExW failed (User might have denied UAC)".to_string())
    }
}

#[cfg(target_os = "windows")]
fn to_pcwstr(s: &str) -> Vec<u16> {
    OsStr::new(s).encode_wide().chain(Some(0)).collect()
}
