#![no_std]

pub struct Sha256 {
    h: [u32; 8],
    len_bits: u64,
    buf: [u8; 64],
    buf_len: usize,
}

impl Sha256 {
    pub fn new() -> Self {
        Self {
            h: [
                0x6a09e667, 0xbb67ae85, 0x3c6ef372, 0xa54ff53a,
                0x510e527f, 0x9b05688c, 0x1f83d9ab, 0x5be0cd19,
            ],
            len_bits: 0,
            buf: [0u8; 64],
            buf_len: 0,
        }
    }

    pub fn update(&mut self, mut data: &[u8]) {
        if data.is_empty() { return; }

        self.len_bits = self.len_bits.wrapping_add((data.len() as u64) * 8);

        if self.buf_len != 0 {
            let need = 64 - self.buf_len;
            let take = core::cmp::min(need, data.len());
            self.buf[self.buf_len..self.buf_len + take].copy_from_slice(&data[..take]);
            self.buf_len += take;
            data = &data[take..];

            if self.buf_len == 64 {
                compress(&mut self.h, &self.buf);
                self.buf_len = 0;
            }
        }

        while data.len() >= 64 {
            let mut block = [0u8; 64];
            block.copy_from_slice(&data[..64]);
            compress(&mut self.h, &block);
            data = &data[64..];
        }

        if !data.is_empty() {
            self.buf[..data.len()].copy_from_slice(data);
            self.buf_len = data.len();
        }
    }

    pub fn finalize(mut self) -> [u8; 32] {
        let mut pad = [0u8; 128];
        pad[0] = 0x80;

        let len_be = self.len_bits.to_be_bytes();

        let rem = self.buf_len;
        let pad_len = if rem < 56 { 56 - rem } else { 64 + 56 - rem };

        self.update(&pad[..pad_len]);
        self.update(&len_be);

        let mut out = [0u8; 32];
        for (i, w) in self.h.iter().enumerate() {
            out[i * 4..i * 4 + 4].copy_from_slice(&w.to_be_bytes());
        }
        out
    }
}

pub fn sha256(data: &[u8]) -> [u8; 32] {
    let mut h = Sha256::new();
    h.update(data);
    h.finalize()
}

#[inline(always)]
fn rotr(x: u32, n: u32) -> u32 { (x >> n) | (x << (32 - n)) }
#[inline(always)]
fn ch(x: u32, y: u32, z: u32) -> u32 { (x & y) ^ ((!x) & z) }
#[inline(always)]
fn maj(x: u32, y: u32, z: u32) -> u32 { (x & y) ^ (x & z) ^ (y & z) }
#[inline(always)]
fn big0(x: u32) -> u32 { rotr(x, 2) ^ rotr(x, 13) ^ rotr(x, 22) }
#[inline(always)]
fn big1(x: u32) -> u32 { rotr(x, 6) ^ rotr(x, 11) ^ rotr(x, 25) }
#[inline(always)]
fn small0(x: u32) -> u32 { rotr(x, 7) ^ rotr(x, 18) ^ (x >> 3) }
#[inline(always)]
fn small1(x: u32) -> u32 { rotr(x, 17) ^ rotr(x, 19) ^ (x >> 10) }

const K: [u32; 64] = [
    0x428a2f98,0x71374491,0xb5c0fbcf,0xe9b5dba5,0x3956c25b,0x59f111f1,0x923f82a4,0xab1c5ed5,
    0xd807aa98,0x12835b01,0x243185be,0x550c7dc3,0x72be5d74,0x80deb1fe,0x9bdc06a7,0xc19bf174,
    0xe49b69c1,0xefbe4786,0x0fc19dc6,0x240ca1cc,0x2de92c6f,0x4a7484aa,0x5cb0a9dc,0x76f988da,
    0x983e5152,0xa831c66d,0xb00327c8,0xbf597fc7,0xc6e00bf3,0xd5a79147,0x06ca6351,0x14292967,
    0x27b70a85,0x2e1b2138,0x4d2c6dfc,0x53380d13,0x650a7354,0x766a0abb,0x81c2c92e,0x92722c85,
    0xa2bfe8a1,0xa81a664b,0xc24b8b70,0xc76c51a3,0xd192e819,0xd6990624,0xf40e3585,0x106aa070,
    0x19a4c116,0x1e376c08,0x2748774c,0x34b0bcb5,0x391c0cb3,0x4ed8aa4a,0x5b9cca4f,0x682e6ff3,
    0x748f82ee,0x78a5636f,0x84c87814,0x8cc70208,0x90befffa,0xa4506ceb,0xbef9a3f7,0xc67178f2,
];

fn compress(h: &mut [u32; 8], block: &[u8; 64]) {
    let mut w = [0u32; 64];
    for t in 0..16 {
        let i = t * 4;
        w[t] = u32::from_be_bytes([block[i], block[i+1], block[i+2], block[i+3]]);
    }
    for t in 16..64 {
        w[t] = small1(w[t-2])
            .wrapping_add(w[t-7])
            .wrapping_add(small0(w[t-15]))
            .wrapping_add(w[t-16]);
    }

    let (mut a, mut b, mut c, mut d) = (h[0], h[1], h[2], h[3]);
    let (mut e, mut f, mut g, mut hh) = (h[4], h[5], h[6], h[7]);

    for t in 0..64 {
        let t1 = hh
            .wrapping_add(big1(e))
            .wrapping_add(ch(e,f,g))
            .wrapping_add(K[t])
            .wrapping_add(w[t]);
        let t2 = big0(a).wrapping_add(maj(a,b,c));
        hh = g; g = f; f = e;
        e = d.wrapping_add(t1);
        d = c; c = b; b = a;
        a = t1.wrapping_add(t2);
    }

    h[0] = h[0].wrapping_add(a);
    h[1] = h[1].wrapping_add(b);
    h[2] = h[2].wrapping_add(c);
    h[3] = h[3].wrapping_add(d);
    h[4] = h[4].wrapping_add(e);
    h[5] = h[5].wrapping_add(f);
    h[6] = h[6].wrapping_add(g);
    h[7] = h[7].wrapping_add(hh);
}
