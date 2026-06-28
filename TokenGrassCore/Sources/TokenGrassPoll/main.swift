import Foundation

// Dev/companion CLI.
//   tokengrass-poll connect → run `claude setup-token`, capture the token, validate
//   tokengrass-poll login   → in-app Claude OAuth login (blocked by Anthropic — kept for reference)
//   tokengrass-poll         → poll /api/oauth/usage + accumulate
let args = CommandLine.arguments.dropFirst()
if args.contains("connect") || args.contains("setup") {
    runConnect()
} else if args.contains("login") {
    runLogin()
} else {
    runPoll()
}
