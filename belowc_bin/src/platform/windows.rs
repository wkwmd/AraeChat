#[no_mangle]
pub unsafe extern "C" fn mainCRTStartup() -> ! {
    let code = crate::run_compiler();
    crate::sys_exit(code);
}
