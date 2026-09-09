# Godot iOS GameCenter plugin

## Methods

### Authorization

`get_plugin_version()` - Returns the fork's git revision, stamped in at build time (Crystal Tempest fork): a short commit hash, `+` appended if built from a dirty tree, or `"unknown"` if not built from a git checkout. Lets a game show which plugin build it is actually linking.  
`authenticate()` - Performs user authentication. Presents the Game Center sign-in sheet if the player is signed out. Generates an `authentication` event.  
`authenticate_silently()` - Like `authenticate()` but never presents the sign-in sheet (Crystal Tempest fork): if the player is already signed in it authenticates silently and generates an `authentication` `ok` event; if signed out it generates an `authentication` `error` event with `error_description` `"interactive sign-in required"` and shows no UI. For a launch-time "connect if possible" with no unprompted sheet; follow up with `authenticate()` from an explicit sign-in button.  
`is_authenticated()` - Returns authentication state. Note this is a cached flag, written only by the authenticate handler; it does NOT change by itself when the system Game Center account is switched.  
`get_player_id()` - Returns the signed-in player's `GKLocalPlayer.gamePlayerID` (stable per player per game), or `""` when nobody is signed in (Crystal Tempest fork). Read live from GameKit, so polling it detects a system-level player switch, which `is_authenticated()` cannot. The same value is on the `authentication` event as `game_player_id`. Note ids are scoped separately in sandbox and production.  

### GameCenter methods

`post_score(Dictionary score_dictionary)` - Reports a score data to iOS `GameCenter`. Generates new event with `post_score` type.  
`award_achievement(Dictionary achievent_dictionary)` - Reports progress of achievement data to iOS `GameCenter`. Generates new event with `award_achievement` type.  
`reset_achievements()` - Resets all achievement progress for the local player. Generates new event with `reset_achievements` type.  
`request_achievements()` - Loads previously submitted achievement progress for the local player from iOS `GameCenter`. Generates new event with `achievements` type.  
`request_achievement_descriptions()` - Downloads the achievement descriptions from iOS `GameCenter`. Generates new event with `achievement_descriptions` type.  
`show_game_center(Dictionary screen_dictionary)` - Displays Game Center information of your game. Generates new event with `show_game_center` type when information screen closes.  
`request_identity_verification_signature()` -  Creates a signature for a third-party server to authenticate the local player. Generates new event with `identity_verification_signature` type.  

### Saved Games (Crystal Tempest fork)

GameKit's Saved Games API (`GKSavedGame`), added for cross-device cloud save.
Every call is asynchronous; the result arrives on the pending-event queue as a
`Dictionary` with a `type` field and `result` of `"ok"` or `"error"` (errors
also carry `error_code` / `error_description`).

`fetch_saved_games()` - Lists the local player's saved games. Event type `saved_games`, with `saved_games` = array of `{ name: String, device: String, modified: int (unix seconds) }`.  
`load_saved_game(String name)` - Loads the data of the saved game with that name (first match). Event type `saved_game_loaded`, with `name` and, on success, `data` (`PackedByteArray`). No match reports `result: "error"`, `error_description: "not found"`.  
`save_game_data(String name, PackedByteArray data)` - Creates or overwrites the named saved game. Event type `saved_game_written`, with `name` and, on success, `device` and `modified`.  
`delete_saved_game(String name)` - Deletes all saved games with that name. Event type `saved_game_deleted`, with `name`.  
`resolve_conflicting_saved_games(String name, PackedByteArray data)` - Replaces every conflicting version most recently reported for `name` (see `saved_game_conflict` below) with `data`. Event type `saved_games_conflict_resolved`, with `name`.  

After `authenticate()` succeeds the plugin registers a `GKLocalPlayerListener`.
When Game Center reports diverged versions of a saved game it pushes one
unsolicited event per name: type `saved_game_conflict`, with `name` and
`versions` = array of `PackedByteArray` (the data of every conflicting
version). Merge them and call `resolve_conflicting_saved_games(name, merged)`.  

### Leaderboard read + submit (Crystal Tempest fork)

Modern `GKLeaderboard` bindings (iOS 14+), for reading ranked entries into a
custom UI. The stock `post_score` (via the deprecated `GKScore`) still works;
these are additive.

`submit_score(String leaderboard_id, int score)` - Submits `score` to the leaderboard via `GKLeaderboard.submitScore(...leaderboardIDs:)` (context 0). Event type `score_submitted`, with `leaderboard_id`.  
`submit_score_with_context(String leaderboard_id, int score, int context)` - Same, but attaches `context` (a non-negative int) to the score as `GKLeaderboardEntry.context`, which `load_leaderboard_scores` surfaces per row as `level`. Same `score_submitted` event. Distinct name so callers can feature-detect it with `Object.has_method`.  
`load_leaderboard_scores(String leaderboard_id, int start_rank, int count)` - Loads `count` global / all-time ranked entries starting at `start_rank` (**1-based**; `count` clamped to 1..100). Loads and caches the `GKLeaderboard` on first use. Event type `leaderboard_scores`, with `leaderboard_id`, `total` (int, total player count) and `scores` = array of `{ rank: int, player: String (displayName), score: int, date: int (unix seconds), level: int (from entry.context) }`.  

## Properties

## Events reporting

`get_pending_event_count()` - Returns number of events pending from plugin to be processed.  
`pop_pending_event()` - Returns first unprocessed plugin event.  
