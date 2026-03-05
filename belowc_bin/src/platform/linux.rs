use core::arch::asm;
use crate::sys::sys_exit;

#[no_mangle]
pub unsafe extern "C" fn _start() -> ! {
    sys_exit(0)
}
