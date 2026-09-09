/*************************************************************************/
/*  game_center.h                                                        */
/*************************************************************************/
/*                       This file is part of:                           */
/*                           GODOT ENGINE                                */
/*                      https://godotengine.org                          */
/*************************************************************************/
/* Copyright (c) 2007-2021 Juan Linietsky, Ariel Manzur.                 */
/* Copyright (c) 2014-2021 Godot Engine contributors (cf. AUTHORS.md).   */
/*                                                                       */
/* Permission is hereby granted, free of charge, to any person obtaining */
/* a copy of this software and associated documentation files (the       */
/* "Software"), to deal in the Software without restriction, including   */
/* without limitation the rights to use, copy, modify, merge, publish,   */
/* distribute, sublicense, and/or sell copies of the Software, and to    */
/* permit persons to whom the Software is furnished to do so, subject to */
/* the following conditions:                                             */
/*                                                                       */
/* The above copyright notice and this permission notice shall be        */
/* included in all copies or substantial portions of the Software.       */
/*                                                                       */
/* THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND,       */
/* EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF    */
/* MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT.*/
/* IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY  */
/* CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT,  */
/* TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE     */
/* SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.                */
/*************************************************************************/

#ifndef GAME_CENTER_H
#define GAME_CENTER_H

#include "core/version.h"

#if VERSION_MAJOR == 4
#include "core/object/class_db.h"
#else
#include "core/object.h"
#endif

class GameCenter : public Object {

	GDCLASS(GameCenter, Object);

	static GameCenter *instance;
	static void _bind_methods();

	List<Variant> pending_events;

	bool authenticated;

	void return_connect_error(const char *p_error_description);

	// Shared body of authenticate() / authenticate_silently(). p_interactive
	// controls only what happens when GameKit hands back a sign-in view
	// controller: true presents it (the historical authenticate() behaviour),
	// false pushes an "interactive sign-in required" authentication error and
	// presents nothing. The silent-success and error paths are identical.
	Error do_authenticate(bool p_interactive);

public:
	Error authenticate();

	// Like authenticate(), but never presents the Game Center sign-in sheet:
	// a signed-out player yields an "authentication" error event instead of
	// UI. For a launch-time "connect if already signed in" with no unprompted
	// sheet. -- Crystal Tempest fork
	Error authenticate_silently();

	bool is_authenticated();

	// The signed-in player's GKLocalPlayer.gamePlayerID - stable per player per
	// game - or "" when nobody is signed in. Read LIVE from GameKit, not from
	// the cached `authenticated` flag, so a system-level Game Center player
	// switch (sign out as A, in as B) is visible just by polling this: the
	// cached flag stays true across such a switch. Same value as the
	// "game_player_id" field on the authentication event. -- Crystal Tempest fork
	String get_player_id();

	Error post_score(Dictionary p_score);
	Error award_achievement(Dictionary p_params);
	void reset_achievements();
	void request_achievements();
	void request_achievement_descriptions();
	Error show_game_center(Dictionary p_params);
	Error request_identity_verification_signature();

	// Saved Games (GameKit GKSavedGame) - added by the Crystal Tempest fork.
	// Each kicks off an async GameKit call and pushes a Dictionary result to
	// the pending-event queue, mirroring the methods above.
	Error fetch_saved_games();
	Error load_saved_game(String p_name);
	Error save_game_data(String p_name, PackedByteArray p_data);
	Error delete_saved_game(String p_name);
	Error resolve_conflicting_saved_games(String p_name, PackedByteArray p_data);

	// Leaderboard read + submit (GKLeaderboard, iOS 14+) - added by the fork.
	// The stock plugin only writes via post_score / GKScore and shows Apple's
	// UI; our LeaderboardWindow needs ranked entries.
	Error submit_score(String p_leaderboard_id, int p_score);
	// Same, but attaches a GKLeaderboardEntry.context to the score (which the
	// read side surfaces as "level"). Distinct name so the C# side can
	// feature-detect it with HasMethod. -- Crystal Tempest fork
	Error submit_score_with_context(String p_leaderboard_id, int p_score, int p_context);
	Error load_leaderboard_scores(String p_leaderboard_id, int p_start_rank, int p_count);

	// The fork's git revision, stamped in at build time (SConstruct). "+" =
	// built from a dirty tree, "unknown" = not built from a git checkout. Lets
	// the game show which plugin build it is actually linking. -- CT fork
	String get_plugin_version();

	// Registers the GKLocalPlayerListener that surfaces conflicting saved
	// games. Called once, after authentication succeeds. Safe to call again.
	void register_saved_games_listener();

	// Appends an event to the pending-event queue. Used by the GameKit
	// completion handlers and by the saved-games conflict listener.
	void push_pending_event(Variant p_event);

	void game_center_closed();

	int get_pending_event_count();
	Variant pop_pending_event();

	static GameCenter *get_singleton();

	GameCenter();
	~GameCenter();
};

#endif
