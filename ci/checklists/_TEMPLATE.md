# Gate: {{GATE_ID}} — {{TITLE}}

## SSOT anchors
- spec/ssot.yaml: {{ANCHORS}}

## Goal
{{GOAL_ONE_LINER}}

## Checks (must pass)
- [ ] Exit code matches SSOT (success=0, any_failure=1) when applicable
- [ ] stderr bytes == 0 (SSOT hard rule)
- [ ] No dynamic memory usage evidence (when gate is ZH/No-DynMem related)
- [ ] Atomic write contamination prevention holds (when gate writes out.bin)
- [ ] Streaming constraints respected (no Vec accumulation) where applicable

## Test vectors
- {{VECTOR_1}}
- {{VECTOR_2}}
- {{VECTOR_3}}

## Evidence artifacts (paths)
- build log: {{PATH_BUILD_LOG}}
- symbol scan: {{PATH_SYMBOL_SCAN}}
- run logs: {{PATH_RUN_LOGS}}
- outputs: {{PATH_OUTPUTS}}

## Notes
{{NOTES}}
