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

print("""
usage:
  renderspike gen-corpus <mixed|log|single> <sizeMB> <output-path>
  renderspike view <corpus-path>
  (benchmark mode arrives in a later task)
""")
exit(64)
