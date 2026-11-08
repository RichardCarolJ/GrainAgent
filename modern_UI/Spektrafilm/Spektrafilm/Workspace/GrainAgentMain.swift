import AppKit
import SwiftUI

@main enum GrainAgentApplication {
    static func main() {
        AppIdentity.migrateDevelopmentPreferences()
        let args = Array(CommandLine.arguments.dropFirst())
        if let door = args.first, door == "cli" || door == "mcp" {
            AgentOutput.takeStdout()
            let argv = door == "cli" ? Array(args.dropFirst()) : ["mcp"]
            Task { @MainActor in exit(await AgentCLI.run(argv)) }
            RunLoop.main.run()
            return
        }
        MainActor.assumeIsolated {
            UserDefaults.standard.register(defaults: ["grainagent.workspace.professional": true,
                "grainagent.modeMorph.preview": true])
            let app = NSApplication.shared
            let delegate = GrainAgentAppDelegate()
            app.delegate = delegate
            app.setActivationPolicy(.regular)
            withExtendedLifetime(delegate) { app.run() }
        }
    }
}

