# EXTENSIONS STATUS (BelowCode v1)

**Release Tag Evidence**
- **Tag:** `v1.0.0-baremetal`
- **Evidence:** GitHub Actions run (Artifacts linked to this specific tag commit)

이 문서는 BelowCode v1의 확장 파이프라인(X-02 ~ X-05) 검증 결과를 선언하며, GitHub Actions 등 CI 시스템이 산출한 물리적 아티팩트(Artifacts) 경로를 증빙 자료로써 매핑하여 **"수학적/절차적 무결원칙"** 을 고정하는 역할을 수행합니다.

## ✅ X-02: Symbol Scanning & Isolation Proof
OS 네이티브 바이너리 분석 툴(`nm`, `otool`, `dumpbin`)을 이용해 최종 바이너리에 단 하나의 외부 심볼(`libc` 포함)도 정적/동적으로 링크되어 있지 않음을 증명합니다.
- Linux 증빙: `ci/logs/x02_symbol_scan.txt` (명령어: `nm -u`)
- macOS 증빙: `ci/logs/x02_symbol_scan.txt` (명령어: `otool -L`)
- Windows 증빙: `ci/logs/x02_symbol_scan.txt` (명령어: `dumpbin /IMPORTS`)
- **요구 결과**: `0 hits` (참조된 외부 기호가 완전히 없을 것)

## ✅ X-03: Fuzzing & Property Tests
참조 인코더(`reference_encoder` 레벨의 `generate_golden`) 또는 자체 생성기를 이용해 수만 번의 무작위 난수 바이트 입력을 주입하여 성공/실패/길이 제약 등 SSOT 규칙의 엣지 케이스를 돌파했음을 증명합니다.
- Linux/macOS 증빙: `ci/logs/x03_fuzzer.txt` (fuzzer.rs 출력)
- Windows 증빙: `ci/logs/x03_fuzzer.txt`
- **요구 결과**: OOM, 패닉, 무한루프 없이 정해진 이터레이션을 100% 정상 탈출 및 PASS.

## ✅ X-04: Reproducible Build Identity (단일 빌드 재현성)
소스코드와 환경이 동일할 때, 생성되는 바이너리의 SHA256 해시가 `Lock` 파일에 박제된 해시와 비트 단위로 일치함을 증명합니다. 
(상태 무결성을 위해 태그 빌드 등에서는 캐시 개입을 배제하며, 로컬/CI 러너 간 동일 머신 반복 빌드 시에도 해시 불일치가 없음을 전제로 합니다.)
- Linux 증빙: `.github/workflows/ci_linux.yml` 빌드 로그 내 `X-04` step 출력 및 `ci/belowc_identity_linux.lock`
- macOS 증빙: `.github/workflows/ci_macos.yml` 빌드 로그 내 `X-04` step 출력 및 `ci/belowc_identity_macos.lock`
- Windows 증빙: `.github/workflows/ci_windows.yml` 빌드 로그 내 `X-04` step 출력 및 `ci/belowc_identity_windows.lock`
- **요구 결과**: `Built Hash == Expected Hash`

## ✅ X-05: SSOT Auto-Regeneration & Freshness
`spec/ssot.lock.md` 의 규칙이 변경되었을 때, 이를 기반으로 골든 테스트 벡터와 입력 산출물이 자동으로 재생성되며, 그것이 최신 상태 체인(`git diff --exit-code`)을 거슬러 올라감 없이 통과했음을 증명합니다.
- Python Lock Validation: GitHub Actions 빌드 로그의 `X-05 SSOT regeneration up-to-date` step 출력 (`gen_from_ssot.py` 통과)
- Rust Golden Regeneration: `ci/logs/x05_ssot_sync.txt` (Rust `generate_golden` 바이너리 실행 결과)
- **요구 결과**: 파이썬 가드레일 통과 및 Rust 참조 생성기 실행 후 `git diff` clean.

---

### 배포(Sealed) 스냅샷
본 레포지토리는 상기 X-02 ~ X-05 까지의 모든 증빙(logs 및 artifacts)이 이상 없이 PASS했음을 확인하기 위해 `v1.0.0-baremetal` 태그로 현재 상태를 영구 봉인하였습니다.
- **CI Artifacts**: `ci-logs-linux`, `ci-logs-macos`, `ci-logs-windows` zip 파일 다운로드로 원본 파일 확인 가능.
