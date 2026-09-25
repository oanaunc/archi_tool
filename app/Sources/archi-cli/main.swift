// Oanarina Archi Tool command-line runner — GPL-3.0-or-later
import Foundation
import ArchiCore

@MainActor func runCLI() async {
    let ed = Editor()
    ed.onLog = { print($0) }
    while let line = readLine() {
        await ed.run(line)
    }
}
await runCLI()
