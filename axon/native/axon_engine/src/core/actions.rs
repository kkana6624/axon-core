use crate::core::keys::Key;
use rustler::NifTaggedEnum;
use serde::Serialize;

#[derive(NifTaggedEnum, Debug, Clone, Copy, Serialize)]
pub enum Action {
    KeyDown(Key),
    KeyUp(Key),
    KeyTap(Key),
    Wait(u32),
}

pub struct SequenceValidator;

impl SequenceValidator {
    pub const MAX_ACTIONS: usize = 256;
    pub const MAX_WAIT_MS: u32 = 10_000;
    pub const MAX_TOTAL_WAIT_MS: u32 = 30_000;

    pub fn validate(actions: &[Action]) -> Result<(), String> {
        if actions.is_empty() {
            return Ok(());
        }

        if actions.len() > Self::MAX_ACTIONS {
            return Err(format!("Too many actions: {} (max {})", actions.len(), Self::MAX_ACTIONS));
        }

        let mut total_wait = 0;
        for action in actions {
            if let Action::Wait(ms) = action {
                if *ms > Self::MAX_WAIT_MS {
                    return Err(format!("Wait too long: {}ms (max {}ms)", ms, Self::MAX_WAIT_MS));
                }
                total_wait += ms;
            }
        }

        if total_wait > Self::MAX_TOTAL_WAIT_MS {
            return Err(format!("Total wait too long: {}ms (max {}ms)", total_wait, Self::MAX_TOTAL_WAIT_MS));
        }

        Ok(())
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::core::keys::Key;

    #[test]
    fn test_validate_ok() {
        let actions = vec![
            Action::KeyDown(Key::VkA),
            Action::Wait(100),
            Action::KeyUp(Key::VkA),
        ];
        assert!(SequenceValidator::validate(&actions).is_ok());
    }

    #[test]
    fn test_validate_too_many_actions() {
        let actions = vec![Action::Wait(1); 257];
        let result = SequenceValidator::validate(&actions);
        assert!(result.is_err());
        assert!(result.unwrap_err().contains("Too many actions"));
    }

    #[test]
    fn test_validate_wait_too_long() {
        let actions = vec![Action::Wait(10_001)];
        let result = SequenceValidator::validate(&actions);
        assert!(result.is_err());
        assert!(result.unwrap_err().contains("Wait too long"));
    }

    #[test]
    fn test_validate_total_wait_too_long() {
        let actions = vec![
            Action::Wait(10_000),
            Action::Wait(10_000),
            Action::Wait(10_000),
            Action::Wait(1),
        ];
        let result = SequenceValidator::validate(&actions);
        assert!(result.is_err());
        assert!(result.unwrap_err().contains("Total wait too long"));
    }
}
