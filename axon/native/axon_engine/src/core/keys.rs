use rustler::NifUnitEnum;
use serde::Serialize;
use strum::{AsRefStr, Display, EnumIter};

#[derive(NifUnitEnum, Debug, Clone, Copy, EnumIter, AsRefStr, Display, Serialize)]
#[strum(serialize_all = "SCREAMING_SNAKE_CASE")]
pub enum Key {
    VkA,
    VkB,
    VkC,
    VkD,
    VkE,
    VkF,
    VkG,
    VkH,
    VkI,
    VkJ,
    VkK,
    VkL,
    VkM,
    VkN,
    VkO,
    VkP,
    VkQ,
    VkR,
    VkS,
    VkT,
    VkU,
    VkV,
    VkW,
    VkX,
    VkY,
    VkZ,
    #[strum(serialize = "VK_LSHIFT")]
    VkLshift,
    #[strum(serialize = "VK_RSHIFT")]
    VkRshift,
    #[strum(serialize = "VK_LCTRL")]
    VkLcontrol,
    #[strum(serialize = "VK_RCTRL")]
    VkRcontrol,
    #[strum(serialize = "VK_LMENU")]
    VkLmenu, // Alt
    #[strum(serialize = "VK_RMENU")]
    VkRmenu,
    #[strum(serialize = "VK_ENTER")]
    VkReturn,
    VkSpace,
    VkBack,
    VkTab,
    VkEscape,
    VkUp,
    VkDown,
    VkLeft,
    VkRight,
}
