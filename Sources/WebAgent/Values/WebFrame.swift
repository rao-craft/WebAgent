import Foundation

/// What a run says as it goes. Its progress reaches the host as notes (`host.note`); the frame carries the answer.
public enum WebFrame: Sendable {
    case answered(WebResult)

    public var result: WebResult? {
        if case .answered(let result) = self { return result }
        return nil
    }
}
