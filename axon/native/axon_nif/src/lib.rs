use rustler::Atom;

rustler::atoms! {
    error,
    ok,
    engine_failure,
    engine_unavailable,
}

#[rustler::nif]
fn available_nif() -> bool {
    cfg!(target_os = "windows")
}

#[rustler::nif]
fn key_down_nif(_key: String) -> Result<Atom, (Atom, Atom, String)> {
    not_implemented_or_unavailable()
}

#[rustler::nif]
fn key_up_nif(_key: String) -> Result<Atom, (Atom, Atom, String)> {
    not_implemented_or_unavailable()
}

#[rustler::nif]
fn key_tap_nif(_key: String) -> Result<Atom, (Atom, Atom, String)> {
    not_implemented_or_unavailable()
}

#[rustler::nif]
fn panic_nif() -> Atom {
    ok()
}

fn not_implemented_or_unavailable() -> Result<Atom, (Atom, Atom, String)> {
    if cfg!(target_os = "windows") {
        Err((error(), engine_failure(), "engine failure".to_string()))
    } else {
        Err((error(), engine_unavailable(), "engine unavailable".to_string()))
    }
}

rustler::init!("Elixir.Axon.Adapters.MacroEngine.NifEngine");
