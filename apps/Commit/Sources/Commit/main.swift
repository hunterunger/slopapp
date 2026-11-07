import CommitCore
import Foundation

// git and ssh run this same executable as their askpass helper (GIT_ASKPASS / SSH_ASKPASS
// point here, with the socket variable set only in git's environment). In that mode it asks
// the running app over its socket, prints the answer and exits, without starting the UI.
let environment = ProcessInfo.processInfo.environment
if environment[AskpassProtocol.socketVariable] != nil, CommandLine.arguments.count >= 2 {
    exit(AskpassClient.main(arguments: CommandLine.arguments, environment: environment))
}

CommitApp.main()
