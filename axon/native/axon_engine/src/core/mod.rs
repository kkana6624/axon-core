pub mod keys;

use keys::Key;
use serde::Serialize;
use strum::IntoEnumIterator;

#[derive(Serialize)]
struct KeyDefinition {
    name: String,
    atom: String,
}

pub fn generate_keycodes_json() -> String {
    let keys: Vec<KeyDefinition> = Key::iter()
        .map(|k| {
            // Elixir's NifUnitEnum converts VkA to :vk_a
            // We use strum's Display for the "name" (e.g. "VK_A")
            // and a manual conversion for the atom name.
            let atom_name = format!("{:?}", k)
                .chars()
                .enumerate()
                .map(|(i, c)| {
                    if i > 0 && c.is_uppercase() {
                        format!("_{}", c.to_lowercase())
                    } else {
                        c.to_lowercase().to_string()
                    }
                })
                .collect::<String>();

            KeyDefinition {
                name: k.to_string(),
                atom: atom_name,
            }
        })
        .collect();

    serde_json::to_string_pretty(&keys).unwrap()
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_generate_keycodes_json_is_deterministic() {
        let json1 = generate_keycodes_json();
        let json2 = generate_keycodes_json();
        assert_eq!(json1, json2);
        assert!(json1.contains("\"name\": \"VK_A\""));
        assert!(json1.contains("\"atom\": \"vk_a\""));
        assert!(json1.contains("\"name\": \"VK_LSHIFT\""));
        assert!(json1.contains("\"atom\": \"vk_lshift\""));
    }
}
