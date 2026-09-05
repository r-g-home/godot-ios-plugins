# Godot iOS GameCenter plugin

## Methods

### Authorization

`authenticate()` - Performs user authentication.  
`is_authenticated()` - Returns authentication state.  

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

## Properties

## Events reporting

`get_pending_event_count()` - Returns number of events pending from plugin to be processed.  
`pop_pending_event()` - Returns first unprocessed plugin event.  
