use rustler::{Atom, Env, NifResult, ResourceArc, Term};
use crate::windows::mdns::MdnsHandle;
use std::sync::Mutex;

// Wrap in Mutex to allow interior mutability if needed, though handle mainly holds daemon
pub struct MdnsResource(Mutex<Option<MdnsHandle>>);

pub fn load(env: Env, _info: Term) -> bool {
    let _ = rustler::resource!(MdnsResource, env);
    true
}

#[rustler::nif]
pub fn start_mdns_nif(service_type: String, instance_name: String, port: u16) -> NifResult<ResourceArc<MdnsResource>> {
    let handle = MdnsHandle::new(&service_type, &instance_name, port)
        .map_err(|e| rustler::Error::RaiseTerm(Box::new(e)))?;
    
    Ok(ResourceArc::new(MdnsResource(Mutex::new(Some(handle)))))
}

#[rustler::nif]
pub fn stop_mdns_nif(resource: ResourceArc<MdnsResource>) -> NifResult<Atom> {
    let mut guard = resource.0.lock().map_err(|_| rustler::Error::RaiseTerm(Box::new("Mutex poisoned")))?;
    *guard = None; // Drop the handle, which triggers unregister/shutdown via Drop trait
    Ok(rustler::types::atom::ok())
}

#[rustler::nif]
pub fn get_wlan_interfaces_nif() -> NifResult<String> {
    match crate::windows::wlan::get_wlan_interfaces() {
        Ok(interfaces) => serde_json::to_string(&interfaces)
            .map_err(|e| rustler::Error::RaiseTerm(Box::new(format!("JSON error: {}", e)))),
        Err(e) => Err(rustler::Error::RaiseTerm(Box::new(e))),
    }
}

#[rustler::nif]
pub fn run_privileged_command_nif(command: String, parameters: String) -> NifResult<Atom> {
    match crate::windows::shell::run_privileged_command(&command, &parameters) {
        Ok(_) => Ok(rustler::types::atom::ok()),
        Err(e) => Err(rustler::Error::RaiseTerm(Box::new(e))),
    }
}
