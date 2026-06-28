import Foundation

// Dev/companion CLI.
//   tokengrass-poll login   → in-app Claude OAuth login (validate the flow end to end)
//   tokengrass-poll         → poll /api/oauth/usage + accumulate
if CommandLine.arguments.dropFirst().contains("login") {
    runLogin()
} else {
    runPoll()
}
