use rustler::{Env, ResourceArc, Term};
use crate::windows::mdns::MdnsHandle;
use std::sync::Mutex;

// Wrap in Mutex to allow interior mutability if needed, though handle mainly holds daemon
pub struct MdnsResource(Mutex<Option<MdnsHandle>>);

pub fn load(env: Env, _info: Term) -> bool {
    #[allow(non_local_definitions)]
    let _ = rustler::resource!(MdnsResource, env);
    true
}

#[rustler::nif]
pub fn start_mdns_nif(service_type: String, instance_name: String, port: u16) -> Result<ResourceArc<MdnsResource>, String> {
    let handle = MdnsHandle::new(&service_type, &instance_name, port)?;
    Ok(ResourceArc::new(MdnsResource(Mutex::new(Some(handle)))))
}

#[rustler::nif]
pub fn stop_mdns_nif(resource: ResourceArc<MdnsResource>) -> String {
    if let Ok(mut guard) = resource.0.lock() {
        *guard = None; // Drop the handle, which triggers unregister/shutdown via Drop trait
        "ok".to_string()
    } else {
        "error".to_string()
    }
}

#[rustler::nif]
pub fn get_wlan_interfaces_nif() -> Result<String, String> {
    match crate::windows::wlan::get_wlan_interfaces() {
        Ok(interfaces) => serde_json::to_string(&interfaces)
            .map_err(|e| format!("JSON error: {}", e)),
        Err(e) => Err(e),
    }
}

#[rustler::nif]
pub fn run_privileged_command_nif(command: String, parameters: String) -> String {
    match crate::windows::shell::run_privileged_command(&command, &parameters) {
        Ok(_) => "ok".to_string(),
        Err(_) => "error".to_string(),
    }
}