import Foundation
import GraniteAgents
import WebCore

/// The web agent's refusals as the answer standard counts them: a web out of reach is `reach` (try later); a call
/// with nothing to look up is one the call can fix.
extension WebError: AgentRefusing {
    public var refusal: AgentRefusal {
        switch self {
        case .nothingAsked: return AgentRefusal(.call, description)
        case .unreachable: return AgentRefusal(.reach, description)
        }
    }
}
