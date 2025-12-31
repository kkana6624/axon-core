use mdns_sd::{ServiceDaemon, ServiceInfo};
use std::collections::HashMap;

pub struct MdnsHandle {
    daemon: ServiceDaemon,
    service_type: String,
    instance_name: String,
}

impl MdnsHandle {
    pub fn new(service_type: &str, instance_name: &str, port: u16) -> Result<Self, String> {
        let daemon = ServiceDaemon::new().map_err(|e| e.to_string())?;

        // Create a service info.
        let host_name = format!("{}.local.", instance_name);
        let properties = HashMap::new();
        // properties.insert("property_1".to_string(), "test".to_string());

        let my_service = ServiceInfo::new(
            service_type,
            instance_name,
            &host_name,
            "", // ip (empty let library resolve)
            port,
            properties,
        )
        .map_err(|e| e.to_string())?;

        // Register with the daemon.
        daemon.register(my_service).map_err(|e| e.to_string())?;

        Ok(MdnsHandle {
            daemon,
            service_type: service_type.to_string(),
            instance_name: instance_name.to_string(),
        })
    }
}

// Ensure unregister on drop
impl Drop for MdnsHandle {
    fn drop(&mut self) {
        let fullname = format!("{}.{}", self.instance_name, self.service_type);
        let _ = self.daemon.unregister(&fullname);
        let _ = self.daemon.shutdown();
    }
}
