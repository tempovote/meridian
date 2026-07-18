import Foundation

// Top-level code. Later tasks extend this entry point with the window and
// benchmark modes; keep this switch the single dispatch point.
let args = CommandLine.arguments
if args.count >= 5, args[1] == "gen-corpus",
   let kind = CorpusKind(rawValue: args[2]), let sizeMB = Int(args[3]) {
    let url = URL(fileURLWithPath: args[4])
    do {
        let start = Date()
        try CorpusGenerator.generate(
            kind: kind, sizeBytes: sizeMB * 1_000_000, seed: 0xC0FFEE, to: url,
        )
        print("generated \(kind.rawValue) corpus, \(sizeMB) MB, in \(Date().timeIntervalSince(start))s at \(url.path)")
        exit(0)
    } catch {
        FileHandle.standardError.write(Data("gen-corpus failed: \(error)\n".utf8))
        exit(2)
    }
}
if args.count >= 3, args[1] == "view" {
    SpikeApp.run(corpusPath: args[2], benchmark: nil)
}
if args.count >= 3, args[1] == "benchmark" {
    var plan = BenchmarkPlan()
    plan.editOnly = args.contains("--edit-only")
    plan.scrollOnly = args.contains("--scroll-only")
    if let velocityArg = args.first(where: { $0.hasPrefix("--scroll-velocity=") }),
       let value = Double(velocityArg.dropFirst("--scroll-velocity=".count)) {
        plan.scrollVelocityMultiplier = value
    }
    SpikeApp.run(corpusPath: args[2], benchmark: plan)
}
// EXPERIMENT 1 (control group, task-5-report.md "## Differentiation
// experiments"): scroll-only benchmark on Apple's own NSTextContentStorage,
// to tell whether Task 5's scroll crash implicates RopeContentManager's
// custom NSTextLocation or TextKit 2 itself. Temporary mode — see
// ControlBenchmark.swift.
if args.count >= 3, args[1] == "benchmark-control" {
    var velocity = 8.0
    if let velocityArg = args.first(where: { $0.hasPrefix("--scroll-velocity=") }),
       let value = Double(velocityArg.dropFirst("--scroll-velocity=".count)) {
        velocity = value
    }
    ControlSpikeApp.run(corpusPath: args[2], scrollVelocityMultiplier: velocity)
}

print("""
usage:
  renderspike gen-corpus <mixed|log|single> <sizeMB> <output-path>
  renderspike view <corpus-path>
  renderspike benchmark <corpus-path> [--edit-only|--scroll-only] [--scroll-velocity=<viewport-heights/sec>]
  renderspike benchmark-control <corpus-path> [--scroll-velocity=<viewport-heights/sec>]  (EXPERIMENT: NSTextContentStorage control group)
""")
exit(64)
