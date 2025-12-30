#[cfg(target_os = "windows")]
use windows::Win32::{
    Foundation::{ERROR_SUCCESS, HANDLE},
    NetworkManagement::WiFi::{
        WlanCloseHandle, WlanEnumInterfaces, WlanFreeMemory, WlanOpenHandle,
        WLAN_INTERFACE_INFO_LIST,
    },
};

use serde::Serialize;

#[derive(Debug, Serialize)]
pub struct WlanInterface {
    pub guid: String,
    pub description: String,
}

pub fn get_wlan_interfaces() -> Result<Vec<WlanInterface>, String> {
    #[cfg(target_os = "windows")]
    unsafe {
        get_wlan_interfaces_impl()
    }
    #[cfg(not(target_os = "windows"))]
    Err("WLAN API unavailable on non-Windows OS".to_string())
}

#[cfg(target_os = "windows")]
unsafe fn get_wlan_interfaces_impl() -> Result<Vec<WlanInterface>, String> {
    let mut negotiated_version = 0;
    let mut client_handle = HANDLE::default();

    let result = WlanOpenHandle(2, None, &mut negotiated_version, &mut client_handle);
    if result != ERROR_SUCCESS.0 {
        return Err(format!("WlanOpenHandle failed: {:?}", result));
    }

    // Ensure handle is closed
    struct WlanHandle(HANDLE);
    impl Drop for WlanHandle {
        fn drop(&mut self) {
            unsafe {
                let _ = WlanCloseHandle(self.0, None);
            }
        }
    }
    let _handle_guard = WlanHandle(client_handle);

    let mut p_interface_list: *mut WLAN_INTERFACE_INFO_LIST = std::ptr::null_mut();
    let result = WlanEnumInterfaces(client_handle, None, &mut p_interface_list);
    if result != ERROR_SUCCESS.0 {
        return Err(format!("WlanEnumInterfaces failed: {:?}", result));
    }

    // Ensure memory is freed
    struct WlanMemory(*mut std::ffi::c_void);
    impl Drop for WlanMemory {
        fn drop(&mut self) {
            unsafe {
                if !self.0.is_null() {
                    WlanFreeMemory(self.0);
                }
            }
        }
    }
    let _memory_guard = WlanMemory(p_interface_list as *mut _);

    let list = &*p_interface_list;
    let mut interfaces = Vec::new();

    let items = std::slice::from_raw_parts(
        list.InterfaceInfo.as_ptr(),
        list.dwNumberOfItems as usize,
    );

    for item in items {
        let guid_string = format!("{:?}", item.InterfaceGuid); // Windows-rs GUID debug impl is standard registry format
        
        let desc_bytes = &item.strInterfaceDescription;
        let desc_len = desc_bytes.iter().position(|&c| c == 0).unwrap_or(desc_bytes.len());
        let description = String::from_utf16_lossy(&desc_bytes[..desc_len]);

        interfaces.push(WlanInterface {
            guid: guid_string,
            description,
        });
    }

    Ok(interfaces)
}
