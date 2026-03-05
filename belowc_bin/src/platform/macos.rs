use core::arch::asm;
use crate::sys::sys_exit;

#[no_mangle]
pub unsafe extern "C" fn _main() -> ! {
    sys_exit(0)
}
