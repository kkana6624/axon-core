use rustler::Atom;
use crate::core::keys::Key;

rustler::atoms! {
    error,
    ok,
    engine_failure,
    engine_unavailable,
}

#[rustler::nif]
pub fn available_nif() -> bool {
    cfg!(target_os = "windows")
}

#[rustler::nif]
pub fn key_down_nif(key: Key) -> Result<Atom, (Atom, Atom, String)> {
    match crate::windows::input::send_key_down(key) {
        Ok(_) => Ok(ok()),
        Err(e) => Err((error(), engine_failure(), e.to_string())),
    }
}

#[rustler::nif]
pub fn key_up_nif(key: Key) -> Result<Atom, (Atom, Atom, String)> {
    match crate::windows::input::send_key_up(key) {
        Ok(_) => Ok(ok()),
        Err(e) => Err((error(), engine_failure(), e.to_string())),
    }
}

#[rustler::nif]
pub fn key_tap_nif(key: Key) -> Result<Atom, (Atom, Atom, String)> {
    match crate::windows::input::send_key_tap(key) {
        Ok(_) => Ok(ok()),
        Err(e) => Err((error(), engine_failure(), e.to_string())),
    }
}

#[rustler::nif]
pub fn panic_nif() -> Atom {
    match crate::windows::input::send_panic() {
        Ok(_) => ok(),
        Err(_) => error(), // Or just return ok() anyway as it's a panic
    }
}

#[rustler::nif]
pub fn dump_keycodes_nif() -> String {
    crate::core::generate_keycodes_json()
}
