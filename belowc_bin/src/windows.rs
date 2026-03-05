#[link(name = "kernel32")]
extern "system" {
    fn ExitProcess(uExitCode: u32) -> !;
}

#[no_mangle]
pub unsafe extern "C" fn mainCRTStartup() -> ! {
    ExitProcess(0)
}
