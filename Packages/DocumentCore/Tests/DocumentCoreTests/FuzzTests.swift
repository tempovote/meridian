import Testing
@testable import DocumentCore

/// #10 — random edit scripts vs a byte-array reference model. 20k ops on PR
/// CI; nightly.yml scales to 1M via MERIDIAN_FUZZ_OPS (10M for the M1 exit
/// review via workflow_dispatch).
@Test func bufferFuzz() {
    var engine = BufferFuzzEngine(seed: FuzzConfig.seed)
    engine.run(operations: FuzzConfig.operations)
}
