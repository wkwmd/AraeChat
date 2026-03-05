#![no_std]
#![no_main]

extern crate alloc;

use alloc::vec::Vec;

use eamen_core::ByteSink;
use crate::sha256::{Sha256, sha256};

// Template-specific SP1 entrypoint
sp1_zkvm::entrypoint!(main);

mod sha256;

const MAX_IN: usize = 1_048_576; // sealed
const ABI_LEN: usize = 113;

fn ssot_tag_hash() -> [u8; 32] {
    // SSOT statement requires the field; the exact derivation must be stable.
    // If you later decide to commit an actual git tag object hash, bump SSOT accordingly.
    sha256(b"v1.0.0-baremetal")
}

struct ShaSink<'a> {
    hasher: &'a mut Sha256,
    len: u64,
}
impl<'a> ShaSink<'a> {
    fn new(hasher: &'a mut Sha256) -> Self { Self { hasher, len: 0 } }
}
impl<'a> ByteSink for ShaSink<'a> {
    fn write(&mut self, bytes: &[u8]) {
        self.hasher.update(bytes);
        self.len += bytes.len() as u64;
    }
}

pub fn main() {
    // Witness: raw bytes, no normalization (sealed)
    let in_bytes: Vec<u8> = sp1_zkvm::io::read();

    let len_in = in_bytes.len() as u64;
    let h_in = sha256(&in_bytes);

    let h_empty = sha256(&[]);
    let mut h_out = h_empty;
    let mut len_out: u64 = 0;
    let mut exit_flag: u8 = 1;

    if in_bytes.len() <= MAX_IN {
        // Enforce “no partial output”: validate whole input first.
        if eamen_core::validate(&in_bytes) {
            let mut out_hasher = Sha256::new();
            let mut sink = ShaSink::new(&mut out_hasher);

            let (exit, lout) = eamen_core::eval(&in_bytes, &mut sink);
            if exit == 0 {
                exit_flag = 0;
                len_out = lout;
                h_out = out_hasher.finalize();
            } else {
                // defensive: should not occur if validate() was true
                exit_flag = 1;
                len_out = 0;
                h_out = h_empty;
            }
        } else {
            // invalid => failure => empty output
            exit_flag = 1;
            len_out = 0;
            h_out = h_empty;
        }
    } else {
        // MAX_IN exceeded => failure => empty output
        exit_flag = 1;
        len_out = 0;
        h_out = h_empty;
    }

    // Build P-ABI-1: 113 bytes
    let tag = ssot_tag_hash();
    let mut abi = [0u8; ABI_LEN];
    let mut off = 0usize;

    abi[off..off + 32].copy_from_slice(&tag); off += 32;
    abi[off..off + 32].copy_from_slice(&h_in); off += 32;
    abi[off..off + 32].copy_from_slice(&h_out); off += 32;
    abi[off..off + 8].copy_from_slice(&len_in.to_le_bytes()); off += 8;
    abi[off..off + 8].copy_from_slice(&len_out.to_le_bytes()); off += 8;
    abi[off] = exit_flag; off += 1;

    if off != ABI_LEN {
        sp1_zkvm::syscalls::abort();
    }

    sp1_zkvm::io::commit_slice(&abi);
}
