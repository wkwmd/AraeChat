use anyhow::{Context, Result};
use sp1_sdk::{include_elf, ProverClient, SP1Stdin};

pub const ABI_LEN: usize = 113;

pub struct ProofBundle {
    pub proof: Vec<u8>,
    pub public_inputs_113: [u8; ABI_LEN],
}

/// Prove + verify E2E.
/// - Witness input: raw bytes (Vec<u8>)
/// - Public output: P-ABI-1 byte string (113 bytes) committed by guest
pub fn prove_and_verify(in_bytes: &[u8]) -> Result<ProofBundle> {
    // Embed guest ELF (name must match guest bin target)
    const GUEST_ELF: &[u8] = include_elf!("zk-backend-sp1-guest");

    // Build stdin to match guest's `io::read::<Vec<u8>>()`
    let mut stdin = SP1Stdin::new();
    let v: Vec<u8> = in_bytes.to_vec();
    stdin.write(&v);

    // Prover client
    let client = ProverClient::new();

    // Setup proving/verifying keys from ELF
    let (pk, vk) = client.setup(GUEST_ELF);

    // Produce proof
    // NOTE: depending on SDK minor differences, this might be:
    // - client.prove(&pk, stdin).run()?
    // - client.prove(&pk, stdin)?
    // Keep this exact call aligned with your sp1-sdk 5.2.4 API.
    let proof_with_pv = client
        .prove(&pk, stdin)
        .run()
        .context("sp1 prove failed")?;

    // Verify
    client
        .verify(&proof_with_pv, &vk)
        .context("sp1 verify failed")?;

    // Extract public values (must be exactly 113 bytes per SSOT)
    let pv_bytes: Vec<u8> = proof_with_pv.public_values.to_vec();
    anyhow::ensure!(
        pv_bytes.len() == ABI_LEN,
        "public inputs length mismatch: got {}, expected {}",
        pv_bytes.len(),
        ABI_LEN
    );

    let mut public_inputs_113 = [0u8; ABI_LEN];
    public_inputs_113.copy_from_slice(&pv_bytes);

    Ok(ProofBundle {
        proof: proof_with_pv.proof.to_vec(),
        public_inputs_113,
    })
}
