import Foundation
import GraniteAgents
import WebCore

/// The web agent's refusals as the answer standard counts them. `reach` (try later) only when the network or the
/// engines stood in the way; a link that answered and could not be read (gone, private, closed) is the call's to fix,
/// so the model changes the call instead of repeating it.
extension WebError: AgentRefusing {
    public var refusal: AgentRefusal {
        switch self {
        case .nothingAsked, .unreadable: return AgentRefusal(.call, description)
        case .unreachable, .enginesDown: return AgentRefusal(.reach, description)
        }
    }
}
