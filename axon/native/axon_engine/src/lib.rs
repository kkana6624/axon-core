pub mod core;
pub mod nif;
pub mod windows;

rustler::init!(
    "Elixir.Axon.Adapters.MacroEngine.NifEngine",
    load = nif::setup::load
);
