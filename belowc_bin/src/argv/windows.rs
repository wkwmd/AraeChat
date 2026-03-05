use core::slice;

#[repr(C)]
struct UnicodeString {
    length: u16,
    maximum_length: u16,
    buffer: *const u16,
}

pub unsafe fn get_cmdline() -> &'static [u16] {
    let peb: *const u8;
    core::arch::asm!(
        "mov {}, gs:[0x60]",
        out(reg) peb,
        options(pure, nomem, nostack)
    );
    // RTL_USER_PROCESS_PARAMETERS offset in PEB is 0x20
    let process_params: *const u8 = *(peb.add(0x20) as *const *const u8);
    // CommandLine offset in RTL_USER_PROCESS_PARAMETERS is 0x70
    let cmdline = &*(process_params.add(0x70) as *const UnicodeString);
    slice::from_raw_parts(cmdline.buffer, (cmdline.length / 2) as usize)
}
