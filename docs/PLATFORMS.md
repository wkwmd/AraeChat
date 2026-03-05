# BelowCode v1 Platform Differences

This document outlines the differences in the `belowc_bin` implementation across supported platforms (Windows, Linux, macOS) under the strict `no_std`, `no_main` environment with a 0-byte stderr policy constraints.

## 1. Entry Points
- **Windows**: The entry point is defined as an un-mangled `mainCRTStartup` function which manually retrieves the command line via `GetCommandLineW()` and establishes the exit sequence with `ExitProcess()`.
- **Linux**: To prevent safe Rust from implicitly corrupting the stack by shifting the `RSP` frame pointer in its prologue before we can read dynamic `argc` and `argv` pointer offsets, a raw `global_asm!` block defines the exact `_start` symbol. It securely aligns the stack (`and rsp, -16`) and passes the arguments to a `rust_start` C-ABI handler.
- **macOS**: Defined via a standard `#[no_mangle] pub unsafe extern "C" fn main(argc: isize, argv: *const *const u8) -> i32`, bypassing the need for strict assembly-level stack hacking.

## 2. Command Line Arguments
- **Windows**: Parses UTF-16 byte strings utilizing `GetCommandLineW()` since Windows' `mainCRTStartup` does not receive standard Unix `argc/argv` pairs.
- **Unix (Linux/macOS)**: Native `argc: isize` and `argv: *const *const u8` are directly read and parsed as C strings natively.

## 3. System Calls
- **Windows**: Direct DLL linking to `kernel32.dll` via `extern "system"` for `CreateFileW`, `ReadFile`, `WriteFile`, `CloseHandle`, `MoveFileExW`, and `DeleteFileW`.
- **Linux**: Direct hardware syscalls using inline `core::arch::asm!` (`"syscall"`) using standard ABI Linux syscall numbers (e.g. `SYS_OPEN = 2`).
- **macOS**: Analogous to Linux but uses BSD-derived system call class prefixes bitshifted on the opcodes (e.g., `0x02000000 | 1` for `SYS_EXIT`).

## 4. Linker Configuration (`.cargo/config.toml`)
- **Unix**: We pass `-C link-arg=-nostartfiles` to instruct the GNU linker not to bundle the standard C runtime initialization files (`crt1.o`, `crti.o`, etc.) which conflict with our custom `_start`/`main`.
- **Implicit C Functions**: We must explicitly define `#![no_mangle]` equivalents for `memset`, `memcpy`, and `memcmp` employing `core::ptr::write_volatile` to prevent OS linking errors. This is required as the LLVM backend implicitly tries to generate links to libc utilities for stack zeroing operations on large array initializations (e.g. `[0u8; 1024]`).

## 5. File System Operations
- **Atomic Renames**: Windows uses `MoveFileExW` with `MOVEFILE_REPLACE_EXISTING`. Unix leverages the standard `rename` syscall which guarantees POSIX standards for atomic index updates.
- **File Modes**: Unix explicit file mode permission literals (e.g., octal `0o666`) must be supplied during `sys_unix::open` when specifying `O_CREAT` constraints to bypass sticky bit defaults.
