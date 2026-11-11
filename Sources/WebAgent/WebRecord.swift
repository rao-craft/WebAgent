import GraniteAgents

/// The web agent's place in Granite's roster: an app that links this package finds the `web` agent by this record,
/// with nothing listed by hand.
@used @section("__DATA_CONST,__granite")
let webRecord: GraniteRoster.Record = { GraniteRoster.record(WebAgent.self) }
