#![no_std]
#![no_main]

mod panic;

#[cfg(target_os = "windows")]
#[path = "platform/windows.rs"]
mod entrypoint;

// Minimal sys_exit just to fulfill Windows First for now.
#[cfg(target_os = "windows")]
pub unsafe fn sys_exit(code: i32) -> ! {
    win::ExitProcess(code as u32)
}

#[cfg(target_os = "windows")]
pub mod win {
    pub const GENERIC_READ: u32 = 0x80000000;
    pub const GENERIC_WRITE: u32 = 0x40000000;
    pub const CREATE_ALWAYS: u32 = 2;
    pub const OPEN_EXISTING: u32 = 3;
    pub const FILE_ATTRIBUTE_NORMAL: u32 = 0x80;
    pub const INVALID_HANDLE_VALUE: isize = -1;
    
    // MOVEFILE_REPLACE_EXISTING | MOVEFILE_WRITE_THROUGH
    pub const MOVEFILE_REPLACE_EXISTING: u32 = 1;
    pub const MOVEFILE_WRITE_THROUGH: u32 = 8;
    
    pub const FILE_INFO_BY_HANDLE_CLASS_FILE_RENAME_INFO: u32 = 3;

    #[repr(C)]
    pub struct FILE_RENAME_INFO {
        pub ReplaceIfExists: u8,
        pub RootDirectory: isize,
        pub FileNameLength: u32,
        pub FileName: [u16; 1], 
    }

    #[link(name = "kernel32")]
    extern "system" {
        pub fn ExitProcess(uExitCode: u32) -> !;
        pub fn GetCommandLineW() -> *const u16;
        pub fn CreateFileW(
            lpFileName: *const u16,
            dwDesiredAccess: u32,
            dwShareMode: u32,
            lpSecurityAttributes: *const u8,
            dwCreationDisposition: u32,
            dwFlagsAndAttributes: u32,
            hTemplateFile: isize,
        ) -> isize;
        pub fn ReadFile(
            hFile: isize,
            lpBuffer: *mut u8,
            nNumberOfBytesToRead: u32,
            lpNumberOfBytesRead: *mut u32,
            lpOverlapped: *mut u8,
        ) -> i32;
        pub fn WriteFile(
            hFile: isize,
            lpBuffer: *const u8,
            nNumberOfBytesToWrite: u32,
            lpNumberOfBytesWritten: *mut u32,
            lpOverlapped: *mut u8,
        ) -> i32;
        pub fn FlushFileBuffers(hFile: isize) -> i32;
        pub fn CloseHandle(hObject: isize) -> i32;
        pub fn DeleteFileW(lpFileName: *const u16) -> i32;
        pub fn SetFileInformationByHandle(
            hFile: isize,
            FileInformationClass: u32,
            lpFileInformation: *const u8,
            dwBufferSize: u32,
        ) -> i32;
        pub fn MoveFileExW(
            lpExistingFileName: *const u16,
            lpNewFileName: *const u16,
            dwFlags: u32,
        ) -> i32;
    }
}

pub struct Utf8Decoder {
    state: u32,
    codep: u32,
}

impl Utf8Decoder {
    pub fn new() -> Self { Self { state: 0, codep: 0 } }
    
    pub fn decode(&mut self, byte: u8) -> Option<u32> {
        if self.state == 0 {
            if byte <= 0x7F {
                return Some(byte as u32);
            } else if byte >> 5 == 0b110 {
                self.codep = (byte as u32 & 0x1F) << 6;
                self.state = 1;
            } else if byte >> 4 == 0b1110 {
                self.codep = (byte as u32 & 0x0F) << 12;
                self.state = 2;
            } else if byte >> 3 == 0b11110 {
                self.codep = (byte as u32 & 0x07) << 18;
                self.state = 3;
            } else {
                return Some(0xFFFD); // Error
            }
        } else {
            if byte >> 6 != 0b10 {
                self.state = 0;
                return Some(0xFFFD); // Error
            }
            let val = (byte as u32) & 0x3F;
            if self.state == 1 {
                let cp = self.codep | val;
                self.state = 0;
                return Some(cp);
            } else if self.state == 2 {
                self.codep |= val << 6;
                self.state = 1;
            } else if self.state == 3 {
                self.codep |= val << 12;
                self.state = 2;
            }
        }
        None
    }
}

pub const LUT: [u32; 8] = [
    0x00000013, 0x00100513, 0x00200513, 0x00300513, 0x00400513, 0x00500513, 0x00600513, 0x00000073,
];

#[cfg(target_os = "windows")]
unsafe fn parse_args(cmdline: *const u16, max_args: usize, out_args: &mut [[u16; 260]]) -> usize {
    let mut p = cmdline;
    let mut count = 0;
    
    while *p != 0 && count < max_args {
        while *p == 32 || *p == 9 { p = p.add(1); }
        if *p == 0 { break; }
        
        let mut in_quotes = false;
        let mut arg_i = 0;
        
        while *p != 0 {
            if *p == 34 {
                in_quotes = !in_quotes;
            } else if (*p == 32 || *p == 9) && !in_quotes {
                break;
            } else {
                if arg_i < 259 {
                    out_args[count][arg_i] = *p;
                    arg_i += 1;
                }
            }
            p = p.add(1);
        }
        out_args[count][arg_i] = 0;
        count += 1;
    }
    count
}

#[cfg(target_os = "windows")]
pub unsafe fn run_compiler() -> i32 {
    let cmdline = win::GetCommandLineW();
    let mut args = [[0u16; 260]; 3];
    let count = parse_args(cmdline, 3, &mut args);
    
    if count != 3 {
        return 1;
    }
    // args[1][0] == '-' (0x002D) -> invalid flag parameter constraint
    if args[1][0] == 0x002D {
        return 1;
    }
    
    let h_in = win::CreateFileW(
        args[1].as_ptr(),
        win::GENERIC_READ,
        1, 
        core::ptr::null(),
        win::OPEN_EXISTING,
        win::FILE_ATTRIBUTE_NORMAL,
        0,
    );
    if h_in == win::INVALID_HANDLE_VALUE { return 1; }
    
    let out_path = &args[2];
    
    // Find basename to construct tmp file path
    let mut last_slash = 0;
    let mut out_len = 0;
    while out_path[out_len] != 0 {
        if out_path[out_len] == 0x005C || out_path[out_len] == 0x002F { // '\' or '/'
            last_slash = out_len + 1;
        }
        out_len += 1;
    }
    
    // Try to open a temporary file, up to 8 times
    let mut tmp_path = [0u16; 260];
    let mut h_out = win::INVALID_HANDLE_VALUE;
    let mut try_count = 0;
    
    let ext_base = [0x002E, 0x0062, 0x0065, 0x006C, 0x006F, 0x0077, 0x0063, 0x002E, 0x0074, 0x006D, 0x0070]; // ".belowc.tmp"
    
    while try_count < 9 && h_out == win::INVALID_HANDLE_VALUE {
        // Copy directory part spanning [0..last_slash] + "." + [basename] + ext_base + [retry_suffix]
        let mut tmp_len = 0;
        while tmp_len < last_slash {
            tmp_path[tmp_len] = out_path[tmp_len];
            tmp_len += 1;
        }
        tmp_path[tmp_len] = 0x002E; // '.'
        tmp_len += 1;
        
        // Append basename
        let mut bz = last_slash;
        while bz < out_len {
            tmp_path[tmp_len] = out_path[bz];
            tmp_len += 1;
            bz += 1;
        }
        
        // Append ext_base
        for c in ext_base {
            tmp_path[tmp_len] = c;
            tmp_len += 1;
        }
        
        if try_count > 0 {
            tmp_path[tmp_len] = 0x002E; // '.'
            tmp_len += 1;
            tmp_path[tmp_len] = 0x0030 + (try_count as u16); // '1'..'8'
            tmp_len += 1;
        }
        
        tmp_path[tmp_len] = 0;
        
        // Try creating without truncation, returning error if it exists (atomic creation constraint)
        const CREATE_NEW: u32 = 1;
        
        h_out = win::CreateFileW(
            tmp_path.as_ptr(),
            win::GENERIC_WRITE,
            0,
            core::ptr::null(),
            CREATE_NEW,
            win::FILE_ATTRIBUTE_NORMAL,
            0,
        );
        
        try_count += 1;
    }
    
    if h_out == win::INVALID_HANDLE_VALUE {
        win::CloseHandle(h_in);
        return 1;
    }
    
    let mut buf = [0u8; 1024];
    let mut decoder = Utf8Decoder::new();
    let mut acc = 0u32;
    let mut line_has_valid = false;
    
    loop {
        let mut bytes_read = 0;
        let res = win::ReadFile(h_in, buf.as_mut_ptr(), buf.len() as u32, &mut bytes_read, core::ptr::null_mut());
        if res == 0 || bytes_read == 0 { break; }
        
        for i in 0..bytes_read as usize {
            if let Some(cp) = decoder.decode(buf[i]) {
                if cp == 0x20 || cp == 0x09 || cp == 0x0D {
                    continue;
                } else if cp == 0x0A {
                    if line_has_valid {
                        let word = LUT[acc as usize];
                        let wbytes = word.to_le_bytes();
                        let mut bw = 0;
                        win::WriteFile(h_out, wbytes.as_ptr(), 4, &mut bw, core::ptr::null_mut());
                    }
                    acc = 0;
                    line_has_valid = false;
                } else {
                    if cp < 0xAC00 || cp > 0xD7A3 { return 1; }
                    let s = cp - 0xAC00;
                    if s % 28 != 0 { return 1; }
                    let state = match (s / 28) % 21 {
                        11 => 0, 0  => 1, 4  => 2, 20 => 3,
                        8  => 4, 13 => 5, 18 => 6, 19 => 7,
                        _  => { return 1; } 
                    };
                    acc = (acc | state) & 7;
                    line_has_valid = true;
                }
            }
        }
    }
    
    if line_has_valid {
        let word = LUT[acc as usize];
        let wbytes = word.to_le_bytes();
        let mut bw = 0;
        win::WriteFile(h_out, wbytes.as_ptr(), 4, &mut bw, core::ptr::null_mut());
    }
    
    // Commit the pipeline outputs
    win::FlushFileBuffers(h_out);
    win::CloseHandle(h_in);
    win::CloseHandle(h_out);

    // Swap atomic handles out to public bin file pointer. Wait for file handles to free from kernel.
    let move_res = win::MoveFileExW(
        tmp_path.as_ptr(), 
        args[2].as_ptr(), 
        win::MOVEFILE_REPLACE_EXISTING | win::MOVEFILE_WRITE_THROUGH
    );
    
    if move_res == 0 {
        // Fallback or explicit cleanup constraint, Move failures signify OS collisions
        win::DeleteFileW(tmp_path.as_ptr());
        return 1;
    }
    
    0
}

#[cfg(unix)]
pub mod sys_unix {
    #[cfg(target_os = "linux")]
    pub const SYS_READ: usize = 0;
    #[cfg(target_os = "linux")]
    pub const SYS_WRITE: usize = 1;
    #[cfg(target_os = "linux")]
    pub const SYS_OPEN: usize = 2;
    #[cfg(target_os = "linux")]
    pub const SYS_CLOSE: usize = 3;
    #[cfg(target_os = "linux")]
    pub const SYS_RENAME: usize = 82;
    #[cfg(target_os = "linux")]
    pub const SYS_UNLINK: usize = 87;
    #[cfg(target_os = "linux")]
    pub const O_CREAT: usize = 0o100;
    #[cfg(target_os = "linux")]
    pub const O_EXCL: usize = 0o200;

    #[cfg(target_os = "macos")]
    pub const SYS_READ: usize = 0x2000003;
    #[cfg(target_os = "macos")]
    pub const SYS_WRITE: usize = 0x2000004;
    #[cfg(target_os = "macos")]
    pub const SYS_OPEN: usize = 0x2000005;
    #[cfg(target_os = "macos")]
    pub const SYS_CLOSE: usize = 0x2000006;
    #[cfg(target_os = "macos")]
    pub const SYS_RENAME: usize = 0x2000080;
    #[cfg(target_os = "macos")]
    pub const SYS_UNLINK: usize = 0x200000a;
    #[cfg(target_os = "macos")]
    pub const O_CREAT: usize = 0x0200;
    #[cfg(target_os = "macos")]
    pub const O_EXCL: usize = 0x0800;

    #[cfg(unix)]
    pub const O_RDONLY: usize = 0;
    #[cfg(unix)]
    pub const O_WRONLY: usize = 1;

    #[inline(always)]
    #[cfg(target_arch = "x86_64")]
    pub unsafe fn syscall(n: usize, a1: usize, a2: usize, a3: usize) -> usize {
        let ret: usize;
        core::arch::asm!(
            "syscall",
            in("rax") n,
            in("rdi") a1,
            in("rsi") a2,
            in("rdx") a3,
            out("rcx") _,
            out("r11") _,
            lateout("rax") ret,
            options(nostack)
        );
        ret
    }

    #[inline(always)]
    #[cfg(target_arch = "aarch64")]
    pub unsafe fn syscall(n: usize, a1: usize, a2: usize, a3: usize) -> usize {
        let ret: usize;
        core::arch::asm!(
            "svc 0",
            in("x16") n,
            in("x0") a1,
            in("x1") a2,
            in("x2") a3,
            lateout("x0") ret,
            options(nostack)
        );
        ret
    }

    #[inline(always)]
    pub unsafe fn open(path: *const u8, flags: usize, mode: usize) -> isize {
        syscall(SYS_OPEN, path as usize, flags, mode) as isize
    }
    
    #[inline(always)]
    pub unsafe fn read(fd: isize, buf: *mut u8, count: usize) -> isize {
        syscall(SYS_READ, fd as usize, buf as usize, count) as isize
    }

    #[inline(always)]
    pub unsafe fn write(fd: isize, buf: *const u8, count: usize) -> isize {
        syscall(SYS_WRITE, fd as usize, buf as usize, count) as isize
    }

    #[inline(always)]
    pub unsafe fn close(fd: isize) -> isize {
        syscall(SYS_CLOSE, fd as usize, 0, 0) as isize
    }

    #[inline(always)]
    pub unsafe fn rename(oldpath: *const u8, newpath: *const u8) -> isize {
        syscall(SYS_RENAME, oldpath as usize, newpath as usize, 0) as isize
    }

    #[inline(always)]
    pub unsafe fn unlink(pathname: *const u8) -> isize {
        syscall(SYS_UNLINK, pathname as usize, 0, 0) as isize
    }
}

#[cfg(all(target_os = "linux", target_arch = "x86_64"))]
core::arch::global_asm!(
    ".intel_syntax noprefix",
    ".global _start",
    "_start:",
    "mov rdi, [rsp]",
    "lea rsi, [rsp + 8]",
    "and rsp, -16",
    "call rust_start",
    "hlt",
    ".att_syntax"
);

#[cfg(all(target_os = "linux", target_arch = "aarch64"))]
core::arch::global_asm!(
    ".global _start",
    "_start:",
    "ldr x0, [sp]",
    "add x1, sp, 8",
    "bic sp, sp, 15",
    "bl rust_start",
    "b ."
);

#[cfg(target_os = "linux")]
#[no_mangle]
pub unsafe extern "C" fn rust_start(argc: isize, argv: *const *const u8) -> ! {
    let code = run_compiler_unix(argc, argv);
    sys_exit_unix(code);
}

#[cfg(target_os = "macos")]
#[no_mangle]
pub unsafe extern "C" fn main(argc: isize, argv: *const *const u8) -> i32 {
    let code = run_compiler_unix(argc, argv);
    sys_exit_unix(code);
}

#[cfg(unix)]
pub unsafe fn sys_exit_unix(code: i32) -> ! {
    #[cfg(all(target_os = "linux", target_arch = "x86_64"))]
    core::arch::asm!(
        "syscall",
        in("rax") 60,
        in("rdi") code,
        options(noreturn)
    );

    #[cfg(all(target_os = "linux", target_arch = "aarch64"))]
    core::arch::asm!(
        "svc 0",
        in("x8") 93,
        in("x0") code,
        options(noreturn)
    );

    #[cfg(all(target_os = "macos", target_arch = "x86_64"))]
    core::arch::asm!(
        "syscall",
        in("rax") 0x2000001,
        in("rdi") code,
        options(noreturn)
    );

    #[cfg(all(target_os = "macos", target_arch = "aarch64"))]
    core::arch::asm!(
        "svc 0",
        in("x16") 1,
        in("x0") code,
        options(noreturn)
    );
}

#[cfg(unix)]
#[no_mangle]
pub unsafe extern "C" fn memset(dest: *mut u8, c: i32, n: usize) -> *mut u8 {
    let mut i = 0;
    while i < n {
        core::ptr::write_volatile(dest.add(i), c as u8);
        i += 1;
    }
    dest
}

#[cfg(unix)]
#[no_mangle]
pub unsafe extern "C" fn memcpy(dest: *mut u8, src: *const u8, n: usize) -> *mut u8 {
    let mut i = 0;
    while i < n {
        core::ptr::write_volatile(dest.add(i), core::ptr::read_volatile(src.add(i)));
        i += 1;
    }
    dest
}

#[cfg(unix)]
#[no_mangle]
pub unsafe extern "C" fn memcmp(s1: *const u8, s2: *const u8, n: usize) -> i32 {
    let mut i = 0;
    while i < n {
        let a = core::ptr::read_volatile(s1.add(i));
        let b = core::ptr::read_volatile(s2.add(i));
        if a != b {
            return a as i32 - b as i32;
        }
        i += 1;
    }
    0
}

#[cfg(target_os = "macos")]
#[no_mangle]
pub unsafe extern "C" fn bzero(s: *mut u8, n: usize) {
    let mut i = 0;
    while i < n {
        core::ptr::write_volatile(s.add(i), 0);
        i += 1;
    }
}

#[cfg(target_os = "macos")]
#[link(name = "System")]
extern "C" {}

#[cfg(unix)]
pub unsafe fn run_compiler_unix(argc: isize, argv: *const *const u8) -> i32 {
    if argc != 3 {
        return 1;
    }
    
    let arg1 = *argv.add(1);
    let arg2 = *argv.add(2);
    
    if *arg1 == 45 { // 0x2D == '-'
        return 1;
    }
    
    let fd_in = sys_unix::open(arg1, sys_unix::O_RDONLY, 0);
    if fd_in < 0 { return 1; }
    
    let out_path = arg2;
    let mut out_len = 0;
    let mut last_slash = 0;
    while *out_path.add(out_len) != 0 {
        if *out_path.add(out_len) == b'/' || *out_path.add(out_len) == b'\\' {
            last_slash = out_len + 1;
        }
        out_len += 1;
    }
    
    let mut tmp_path = [0u8; 1024];
    let mut fd_out = -1isize;
    let mut try_count = 0;
    
    let ext_base = b".belowc.tmp";
    
    while try_count < 9 && fd_out < 0 {
        let mut tmp_len = 0;
        while tmp_len < last_slash {
            tmp_path[tmp_len] = *out_path.add(tmp_len);
            tmp_len += 1;
        }
        if last_slash > 0 {
            tmp_path[tmp_len] = b'.';
            tmp_len += 1;
        } else {
            tmp_path[tmp_len] = b'.';
            tmp_len += 1;
        }
        
        let mut bz = last_slash;
        while bz < out_len {
            tmp_path[tmp_len] = *out_path.add(bz);
            tmp_len += 1;
            bz += 1;
        }
        
        for c in ext_base {
            tmp_path[tmp_len] = *c;
            tmp_len += 1;
        }
        
        if try_count > 0 {
            tmp_path[tmp_len] = b'.';
            tmp_len += 1;
            tmp_path[tmp_len] = b'0' + (try_count as u8);
            tmp_len += 1;
        }
        
        tmp_path[tmp_len] = 0;
        
        fd_out = sys_unix::open(tmp_path.as_ptr(), sys_unix::O_WRONLY | sys_unix::O_CREAT | sys_unix::O_EXCL, 0o666);
        try_count += 1;
    }
    
    if fd_out < 0 {
        sys_unix::close(fd_in);
        return 1;
    }

    let mut buf = [0u8; 1024];
    let mut decoder = Utf8Decoder::new();
    let mut acc = 0u32;
    let mut line_has_valid = false;
    
    loop {
        let bytes_read = sys_unix::read(fd_in, buf.as_mut_ptr(), buf.len());
        if bytes_read < 0 { return 1; } // Read error
        if bytes_read == 0 { break; }    // EOF
        
        for i in 0..bytes_read as usize {
            if let Some(cp) = decoder.decode(buf[i]) {
                if cp == 0x20 || cp == 0x09 || cp == 0x0D {
                    continue;
                } else if cp == 0x0A {
                    if line_has_valid {
                        let word = LUT[acc as usize];
                        let wbytes = word.to_le_bytes();
                        sys_unix::write(fd_out, wbytes.as_ptr(), 4);
                    }
                    acc = 0;
                    line_has_valid = false;
                } else {
                    if cp < 0xAC00 || cp > 0xD7A3 { return 1; }
                    let s = cp - 0xAC00;
                    if s % 28 != 0 { return 1; }
                    let state = match (s / 28) % 21 {
                        11 => 0, 0  => 1, 4  => 2, 20 => 3,
                        8  => 4, 13 => 5, 18 => 6, 19 => 7,
                        _  => { return 1; } 
                    };
                    acc = (acc | state) & 7;
                    line_has_valid = true;
                }
            }
        }
    }
    
    if line_has_valid {
        let word = LUT[acc as usize];
        let wbytes = word.to_le_bytes();
        sys_unix::write(fd_out, wbytes.as_ptr(), 4);
    }
    
    sys_unix::close(fd_in);
    sys_unix::close(fd_out);
    
    let r = sys_unix::rename(tmp_path.as_ptr(), out_path);
    if r < 0 {
        sys_unix::unlink(tmp_path.as_ptr());
        return 1;
    }
    
    0
}