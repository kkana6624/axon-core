use crate::core::keys::Key;
use crate::core::actions::Action;

#[cfg(target_os = "windows")]
use windows::Win32::UI::Input::KeyboardAndMouse::{
    SendInput, INPUT, INPUT_0, INPUT_KEYBOARD, KEYBDINPUT, KEYEVENTF_KEYUP,
    VIRTUAL_KEY,
};
#[cfg(target_os = "windows")]
use windows::Win32::Foundation::GetLastError;
#[cfg(target_os = "windows")]
use std::mem::size_of;

pub fn send_key_down(key: Key) -> Result<(), String> {
    #[cfg(target_os = "windows")]
    {
        send_input_impl(key, false)
    }
    #[cfg(not(target_os = "windows"))]
    {
        let _ = key;
        Err("Engine unavailable on non-Windows OS".to_string())
    }
}

pub fn send_key_up(key: Key) -> Result<(), String> {
    #[cfg(target_os = "windows")]
    {
        send_input_impl(key, true)
    }
    #[cfg(not(target_os = "windows"))]
    {
        let _ = key;
        Err("Engine unavailable on non-Windows OS".to_string())
    }
}

pub fn send_key_tap(key: Key) -> Result<(), String> {
    send_key_down(key)?;
    send_key_up(key)
}

pub fn send_sequence(actions: Vec<Action>) -> Result<(), String> {
    #[cfg(target_os = "windows")]
    {
        crate::core::actions::SequenceValidator::validate(&actions)?;
        for action in actions {
            match action {
                Action::KeyDown(key) => send_key_down(key)?,
                Action::KeyUp(key) => send_key_up(key)?,
                Action::KeyTap(key) => send_key_tap(key)?,
                Action::Wait(ms) => std::thread::sleep(std::time::Duration::from_millis(ms as u64)),
            }
        }
        Ok(())
    }
    #[cfg(not(target_os = "windows"))]
    {
        let _ = actions;
        Err("Engine unavailable on non-Windows OS".to_string())
    }
}

pub fn send_panic() -> Result<(), String> {
    #[cfg(target_os = "windows")]
    {
        use strum::IntoEnumIterator;
        for key in Key::iter() {
            let _ = send_key_up(key);
        }
        Ok(())
    }
    #[cfg(not(target_os = "windows"))]
    {
        Err("Engine unavailable on non-Windows OS".to_string())
    }
}

#[cfg(target_os = "windows")]
fn send_input_impl(key: Key, key_up: bool) -> Result<(), String> {
    let vk = map_key_to_vk(key);

    let mut flags = 0;
    if key_up {
        flags |= KEYEVENTF_KEYUP.0;
    }

    let input = INPUT {
        r#type: INPUT_KEYBOARD,
        Anonymous: INPUT_0 {
            ki: KEYBDINPUT {
                wVk: VIRTUAL_KEY(vk),
                wScan: 0,
                dwFlags: windows::Win32::UI::Input::KeyboardAndMouse::KEYBD_EVENT_FLAGS(flags),
                time: 0,
                dwExtraInfo: 0,
            },
        },
    };

    let inputs = [input];
    let sent = unsafe { SendInput(&inputs, size_of::<INPUT>() as i32) };

    if sent != 1 {
        let err = unsafe { GetLastError() };
        return Err(format!("SendInput failed: {:?}", err));
    }

    Ok(())
}

#[cfg(target_os = "windows")]
fn map_key_to_vk(key: Key) -> u16 {
    // Windows Virtual-Key Codes: https://learn.microsoft.com/en-us/windows/win32/inputdev/virtual-key-codes
    match key {
        Key::VkA => 0x41,
        Key::VkB => 0x42,
        Key::VkC => 0x43,
        Key::VkD => 0x44,
        Key::VkE => 0x45,
        Key::VkF => 0x46,
        Key::VkG => 0x47,
        Key::VkH => 0x48,
        Key::VkI => 0x49,
        Key::VkJ => 0x4A,
        Key::VkK => 0x4B,
        Key::VkL => 0x4C,
        Key::VkM => 0x4D,
        Key::VkN => 0x4E,
        Key::VkO => 0x4F,
        Key::VkP => 0x50,
        Key::VkQ => 0x51,
        Key::VkR => 0x52,
        Key::VkS => 0x53,
        Key::VkT => 0x54,
        Key::VkU => 0x55,
        Key::VkV => 0x56,
        Key::VkW => 0x57,
        Key::VkX => 0x58,
        Key::VkY => 0x59,
        Key::VkZ => 0x5A,
        Key::VkLshift => 0xA0,
        Key::VkRshift => 0xA1,
        Key::VkLcontrol => 0xA2,
        Key::VkRcontrol => 0xA3,
        Key::VkLmenu => 0xA4,
        Key::VkRmenu => 0xA5,
        Key::VkReturn => 0x0D,
        Key::VkSpace => 0x20,
        Key::VkBack => 0x08,
        Key::VkTab => 0x09,
        Key::VkEscape => 0x1B,
        Key::VkUp => 0x26,
        Key::VkDown => 0x28,
        Key::VkLeft => 0x25,
        Key::VkRight => 0x27,
    }
}
