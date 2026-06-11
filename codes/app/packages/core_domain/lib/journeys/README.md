# journeys/

Placeholder for the R2 journey engine (Tessera Revolution spec §4.2/§7).

R2 adds the typed journey state machines here — `sealed class` states with
explicit `advance()` transitions for the four journeys (voter, blind-voter,
live-voter, organizer). They are pure Dart so flow enforcement is testable
without widgets; router guards and screens render these states.

Nothing in this directory yet — R1 is extraction only (zero behavior change).
