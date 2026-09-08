/*************************************************************************/
/*  game_center.mm                                                       */
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

#include "game_center.h"

#import "game_center_delegate.h"

#if VERSION_MAJOR == 4
#if VERSION_MINOR >= 6
#import "drivers/apple_embedded/godot_app_delegate.h"
#import "drivers/apple_embedded/godot_view_controller.h"
#elif VERSION_MINOR >= 5
#import "drivers/apple_embedded/godot_app_delegate.h"
#import "drivers/apple_embedded/view_controller.h"
#else
#import "platform/ios/app_delegate.h"
#import "platform/ios/view_controller.h"
#endif
#else
#import "platform/iphone/app_delegate.h"
#import "platform/iphone/view_controller.h"
#endif

#import <GameKit/GameKit.h>

// Stock plugin used [[UIApplication sharedApplication] delegate].window
// .rootViewController, which is nil on Godot 4.5+ (apple_embedded). Resolve
// from the key window at present-time instead. -- Crystal Tempest fork
static UIViewController *gc_top_view_controller() {
	NSArray<UIWindow *> *windows = [UIApplication sharedApplication].windows;
	UIWindow *window = nil;
	for (UIWindow *w in windows) {
		if (w.isKeyWindow) { window = w; break; }
	}
	if (window == nil) {
		for (UIWindow *w in windows) {
			if (w.rootViewController != nil) { window = w; break; }
		}
	}
	UIViewController *vc = window.rootViewController;
	while (vc.presentedViewController != nil) { vc = vc.presentedViewController; }
	return vc;
}

#if VERSION_MAJOR == 4
typedef PackedStringArray GodotStringArray;
typedef PackedInt32Array GodotIntArray;
typedef PackedFloat32Array GodotFloatArray;
#else
typedef PoolStringArray GodotStringArray;
typedef PoolIntArray GodotIntArray;
typedef PoolRealArray GodotFloatArray;
#endif

GameCenter *GameCenter::instance = NULL;
GodotGameCenterDelegate *gameCenterDelegate = nil;

// --- Saved Games (GKSavedGame) support - Crystal Tempest fork ----------------

// Versions handed to us by player:hasConflictingSavedGames:, keyed by saved
// game name. resolve_conflicting_saved_games() consumes the matching entry.
static NSMutableDictionary<NSString *, NSArray<GKSavedGame *> *> *gc_conflicting_games = nil;

@interface GodotGameCenterSavedGamesListener : NSObject <GKLocalPlayerListener>
@end

static GodotGameCenterSavedGamesListener *gc_saved_games_listener = nil;
static bool gc_saved_games_listener_registered = false;

// GKLeaderboard instances, cached by leaderboard ID after the first load so
// repeated load_leaderboard_scores() calls skip loadLeaderboardsWithIDs.
static NSMutableDictionary<NSString *, GKLeaderboard *> *gc_leaderboards = nil;

static NSData *gc_nsdata_from_packed(const PackedByteArray &p_data) {
	if (p_data.size() <= 0) {
		return [NSData data];
	}
	return [NSData dataWithBytes:(const void *)p_data.ptr() length:(NSUInteger)p_data.size()];
}

static PackedByteArray gc_packed_from_nsdata(NSData *p_data) {
	PackedByteArray out;
	if (p_data == nil || p_data.length == 0) {
		return out;
	}
	if (out.resize((int)p_data.length) != OK) {
		return PackedByteArray();
	}
	[p_data getBytes:(void *)out.ptrw() length:p_data.length];
	return out;
}

static String gc_string_from_nsstring(NSString *p_str) {
	if (p_str == nil) {
		return String();
	}
	const char *utf8 = [p_str UTF8String];
	return String::utf8(utf8 != NULL ? utf8 : "");
}

static Dictionary gc_saved_game_to_dict(GKSavedGame *p_game) {
	Dictionary d;
	d["name"] = gc_string_from_nsstring(p_game.name);
	d["device"] = gc_string_from_nsstring(p_game.deviceName);
	d["modified"] = p_game.modificationDate ? (int64_t)[p_game.modificationDate timeIntervalSince1970] : (int64_t)0;
	return d;
}

// Runs GKLeaderboard.loadEntries on an already-loaded board and pushes the
// "leaderboard_scores" event. Shared by the cached and freshly-loaded paths.
static void gc_load_leaderboard_entries(GKLeaderboard *p_board, NSString *p_leaderboard_id, NSRange p_range) {
	[p_board loadEntriesForPlayerScope:GKLeaderboardPlayerScopeGlobal
							timeScope:GKLeaderboardTimeScopeAllTime
								range:p_range
					completionHandler:^(GKLeaderboardEntry *local_player_entry, NSArray<GKLeaderboardEntry *> *entries, NSInteger total_player_count, NSError *error) {
						Dictionary ret;
						ret["type"] = "leaderboard_scores";
						ret["leaderboard_id"] = gc_string_from_nsstring(p_leaderboard_id);
						if (error == nil) {
							ret["result"] = "ok";
							ret["total"] = (int64_t)total_player_count;
							Array scores;
							for (GKLeaderboardEntry *entry in entries) {
								Dictionary row;
								row["rank"] = (int64_t)entry.rank;
								row["player"] = gc_string_from_nsstring(entry.player.displayName);
								row["score"] = (int64_t)entry.score;
								row["date"] = entry.date ? (int64_t)[entry.date timeIntervalSince1970] : (int64_t)0;
								row["level"] = (int64_t)entry.context;
								scores.push_back(row);
							}
							ret["scores"] = scores;
						} else {
							ret["result"] = "error";
							ret["error_code"] = (int64_t)error.code;
							ret["error_description"] = [error.localizedDescription UTF8String];
						}

						if (GameCenter::get_singleton()) {
							GameCenter::get_singleton()->push_pending_event(ret);
						}
					}];
}

void GameCenter::_bind_methods() {
	ClassDB::bind_method(D_METHOD("authenticate"), &GameCenter::authenticate);
	ClassDB::bind_method(D_METHOD("authenticate_silently"), &GameCenter::authenticate_silently);
	ClassDB::bind_method(D_METHOD("is_authenticated"), &GameCenter::is_authenticated);

	ClassDB::bind_method(D_METHOD("post_score"), &GameCenter::post_score);
	ClassDB::bind_method(D_METHOD("award_achievement", "achievement"), &GameCenter::award_achievement);
	ClassDB::bind_method(D_METHOD("reset_achievements"), &GameCenter::reset_achievements);
	ClassDB::bind_method(D_METHOD("request_achievements"), &GameCenter::request_achievements);
	ClassDB::bind_method(D_METHOD("request_achievement_descriptions"), &GameCenter::request_achievement_descriptions);
	ClassDB::bind_method(D_METHOD("show_game_center"), &GameCenter::show_game_center);
	ClassDB::bind_method(D_METHOD("request_identity_verification_signature"), &GameCenter::request_identity_verification_signature);

	ClassDB::bind_method(D_METHOD("fetch_saved_games"), &GameCenter::fetch_saved_games);
	ClassDB::bind_method(D_METHOD("load_saved_game", "name"), &GameCenter::load_saved_game);
	ClassDB::bind_method(D_METHOD("save_game_data", "name", "data"), &GameCenter::save_game_data);
	ClassDB::bind_method(D_METHOD("delete_saved_game", "name"), &GameCenter::delete_saved_game);
	ClassDB::bind_method(D_METHOD("resolve_conflicting_saved_games", "name", "data"), &GameCenter::resolve_conflicting_saved_games);

	ClassDB::bind_method(D_METHOD("submit_score", "leaderboard_id", "score"), &GameCenter::submit_score);
	ClassDB::bind_method(D_METHOD("load_leaderboard_scores", "leaderboard_id", "start_rank", "count"), &GameCenter::load_leaderboard_scores);

	ClassDB::bind_method(D_METHOD("get_pending_event_count"), &GameCenter::get_pending_event_count);
	ClassDB::bind_method(D_METHOD("pop_pending_event"), &GameCenter::pop_pending_event);
};

Error GameCenter::authenticate() {
	return do_authenticate(true);
}

Error GameCenter::authenticate_silently() {
	return do_authenticate(false);
}

Error GameCenter::do_authenticate(bool p_interactive) {
	//if this class isn't available, game center isn't implemented
	if ((NSClassFromString(@"GKLocalPlayer")) == nil) {
		return ERR_UNAVAILABLE;
	}

	GKLocalPlayer *player = [GKLocalPlayer localPlayer];
	ERR_FAIL_COND_V(![player respondsToSelector:@selector(authenticateHandler)], ERR_UNAVAILABLE);

	// This handler is called several times.  First when the view needs to be shown, then again
	// after the view is cancelled or the user logs in.  Or if the user's already logged in, it's
	// called just once to confirm they're authenticated.  This is why no result needs to be specified
	// in the presentViewController phase. In this case, more calls to this function will follow.
	_weakify(player);
	player.authenticateHandler = (^(UIViewController *controller, NSError *error) {
		_strongify(player);

		if (controller) {
			if (!p_interactive) {
				// Silent request: a signed-out player needs the sheet, which
				// the caller did not ask for. Report it, present nothing.
				Dictionary ret;
				ret["type"] = "authentication";
				ret["result"] = "error";
				ret["error_description"] = "interactive sign-in required";
				GameCenter::get_singleton()->authenticated = false;
				pending_events.push_back(ret);
				return;
			}
			UIViewController *root_controller = gc_top_view_controller();
			if (root_controller) {
				[root_controller presentViewController:controller animated:YES completion:nil];
			} else {
				NSLog(@"GameCenter: no view controller available to present the sign-in UI");
			}
		} else {
			Dictionary ret;
			ret["type"] = "authentication";
			if (player.isAuthenticated) {
				ret["result"] = "ok";
				ret["alias"] = [player.alias UTF8String];
				ret["displayName"] = [player.displayName UTF8String];

				if (@available(iOS 13, *)) {
					ret["player_id"] = [player.teamPlayerID UTF8String];
				} else {
					ret["player_id"] = [player.playerID UTF8String];
				}

				GameCenter::get_singleton()->authenticated = true;
				GameCenter::get_singleton()->register_saved_games_listener();
			} else {
				ret["result"] = "error";
				ret["error_code"] = (int64_t)error.code;
				ret["error_description"] = [error.localizedDescription UTF8String];
				GameCenter::get_singleton()->authenticated = false;
			};

			pending_events.push_back(ret);
		};
	});

	return OK;
};

bool GameCenter::is_authenticated() {
	return authenticated;
};

Error GameCenter::post_score(Dictionary p_score) {
	ERR_FAIL_COND_V(!p_score.has("score") || !p_score.has("category"), ERR_INVALID_PARAMETER);
	float score = p_score["score"];
	String category = p_score["category"];

	NSString *cat_str = [[NSString alloc] initWithUTF8String:category.utf8().get_data()];
	GKScore *reporter = [[GKScore alloc] initWithLeaderboardIdentifier:cat_str];
	reporter.value = score;

	ERR_FAIL_COND_V([GKScore respondsToSelector:@selector(reportScores)], ERR_UNAVAILABLE);

	[GKScore reportScores:@[ reporter ]
			withCompletionHandler:^(NSError *error) {
				Dictionary ret;
				ret["type"] = "post_score";
				if (error == nil) {
					ret["result"] = "ok";
				} else {
					ret["result"] = "error";
					ret["error_code"] = (int64_t)error.code;
					ret["error_description"] = [error.localizedDescription UTF8String];
				};

				pending_events.push_back(ret);
			}];

	return OK;
};

Error GameCenter::award_achievement(Dictionary p_params) {
	ERR_FAIL_COND_V(!p_params.has("name") || !p_params.has("progress"), ERR_INVALID_PARAMETER);
	String name = p_params["name"];
	float progress = p_params["progress"];

	NSString *name_str = [[NSString alloc] initWithUTF8String:name.utf8().get_data()];
	GKAchievement *achievement = [[GKAchievement alloc] initWithIdentifier:name_str];
	ERR_FAIL_COND_V(!achievement, FAILED);

	ERR_FAIL_COND_V([GKAchievement respondsToSelector:@selector(reportAchievements)], ERR_UNAVAILABLE);

	achievement.percentComplete = progress;
	achievement.showsCompletionBanner = NO;
	if (p_params.has("show_completion_banner")) {
		achievement.showsCompletionBanner = p_params["show_completion_banner"] ? YES : NO;
	}

	[GKAchievement reportAchievements:@[ achievement ]
				withCompletionHandler:^(NSError *error) {
					Dictionary ret;
					ret["type"] = "award_achievement";
					if (error == nil) {
						ret["result"] = "ok";
					} else {
						ret["result"] = "error";
						ret["error_code"] = (int64_t)error.code;
					};

					pending_events.push_back(ret);
				}];

	return OK;
};

void GameCenter::request_achievement_descriptions() {
	[GKAchievementDescription loadAchievementDescriptionsWithCompletionHandler:^(NSArray *descriptions, NSError *error) {
		Dictionary ret;
		ret["type"] = "achievement_descriptions";
		if (error == nil) {
			ret["result"] = "ok";
			GodotStringArray names;
			GodotStringArray titles;
			GodotStringArray unachieved_descriptions;
			GodotStringArray achieved_descriptions;
			GodotIntArray maximum_points;
			Array hidden;
			Array replayable;

			for (NSUInteger i = 0; i < [descriptions count]; i++) {

				GKAchievementDescription *description = [descriptions objectAtIndex:i];

				const char *str = [description.identifier UTF8String];
				names.push_back(String::utf8(str != NULL ? str : ""));

				str = [description.title UTF8String];
				titles.push_back(String::utf8(str != NULL ? str : ""));

				str = [description.unachievedDescription UTF8String];
				unachieved_descriptions.push_back(String::utf8(str != NULL ? str : ""));

				str = [description.achievedDescription UTF8String];
				achieved_descriptions.push_back(String::utf8(str != NULL ? str : ""));

				maximum_points.push_back(description.maximumPoints);

				hidden.push_back(description.hidden == YES);

				replayable.push_back(description.replayable == YES);
			}

			ret["names"] = names;
			ret["titles"] = titles;
			ret["unachieved_descriptions"] = unachieved_descriptions;
			ret["achieved_descriptions"] = achieved_descriptions;
			ret["maximum_points"] = maximum_points;
			ret["hidden"] = hidden;
			ret["replayable"] = replayable;

		} else {
			ret["result"] = "error";
			ret["error_code"] = (int64_t)error.code;
		};

		pending_events.push_back(ret);
	}];
};

void GameCenter::request_achievements() {
	[GKAchievement loadAchievementsWithCompletionHandler:^(NSArray *achievements, NSError *error) {
		Dictionary ret;
		ret["type"] = "achievements";
		if (error == nil) {
			ret["result"] = "ok";
			GodotStringArray names;
			GodotFloatArray percentages;

			for (NSUInteger i = 0; i < [achievements count]; i++) {

				GKAchievement *achievement = [achievements objectAtIndex:i];
				const char *str = [achievement.identifier UTF8String];
				names.push_back(String::utf8(str != NULL ? str : ""));

				percentages.push_back(achievement.percentComplete);
			}

			ret["names"] = names;
			ret["progress"] = percentages;

		} else {
			ret["result"] = "error";
			ret["error_code"] = (int64_t)error.code;
		};

		pending_events.push_back(ret);
	}];
};

void GameCenter::reset_achievements() {
	[GKAchievement resetAchievementsWithCompletionHandler:^(NSError *error) {
		Dictionary ret;
		ret["type"] = "reset_achievements";
		if (error == nil) {
			ret["result"] = "ok";
		} else {
			ret["result"] = "error";
			ret["error_code"] = (int64_t)error.code;
		};

		pending_events.push_back(ret);
	}];
};

Error GameCenter::show_game_center(Dictionary p_params) {
	ERR_FAIL_COND_V(!NSProtocolFromString(@"GKGameCenterControllerDelegate"), FAILED);

	GKGameCenterViewControllerState view_state = GKGameCenterViewControllerStateDefault;
	if (p_params.has("view")) {
		String view_name = p_params["view"];
		if (view_name == "default") {
			view_state = GKGameCenterViewControllerStateDefault;
		} else if (view_name == "leaderboards") {
			view_state = GKGameCenterViewControllerStateLeaderboards;
		} else if (view_name == "achievements") {
			view_state = GKGameCenterViewControllerStateAchievements;
		} else if (view_name == "challenges") {
			view_state = GKGameCenterViewControllerStateChallenges;
		} else {
			return ERR_INVALID_PARAMETER;
		}
	}

	GKGameCenterViewController *controller = [[GKGameCenterViewController alloc] init];
	ERR_FAIL_COND_V(!controller, FAILED);

	UIViewController *root_controller = gc_top_view_controller();
	ERR_FAIL_COND_V(!root_controller, FAILED);

	controller.gameCenterDelegate = gameCenterDelegate;
	controller.viewState = view_state;
	if (view_state == GKGameCenterViewControllerStateLeaderboards) {
		controller.leaderboardIdentifier = nil;
		if (p_params.has("leaderboard_name")) {
			String name = p_params["leaderboard_name"];
			NSString *name_str = [[NSString alloc] initWithUTF8String:name.utf8().get_data()];
			controller.leaderboardIdentifier = name_str;
		}
	}

	[root_controller presentViewController:controller animated:YES completion:nil];

	return OK;
};

Error GameCenter::request_identity_verification_signature() {
	ERR_FAIL_COND_V(!is_authenticated(), ERR_UNAUTHORIZED);

	GKLocalPlayer *player = [GKLocalPlayer localPlayer];
	void (^verificationSignatureHandler)(NSURL *publicKeyUrl, NSData *signature, NSData *salt, uint64_t timestamp, NSError *error) = ^(NSURL *publicKeyUrl, NSData *signature, NSData *salt, uint64_t timestamp, NSError *error) {
		Dictionary ret;
		ret["type"] = "identity_verification_signature";
		if (error == nil) {
			ret["result"] = "ok";
			ret["public_key_url"] = [publicKeyUrl.absoluteString UTF8String];
			ret["signature"] = [[signature base64EncodedStringWithOptions:0] UTF8String];
			ret["salt"] = [[salt base64EncodedStringWithOptions:0] UTF8String];
			ret["timestamp"] = timestamp;
			if (@available(iOS 13.5, *)) {
				ret["player_id"] = [player.teamPlayerID UTF8String];
			} else {
				ret["player_id"] = [player.playerID UTF8String];
			}
		} else {
			ret["result"] = "error";
			ret["error_code"] = (int64_t)error.code;
			ret["error_description"] = [error.localizedDescription UTF8String];
		};

		pending_events.push_back(ret);
	};

	if (@available(iOS 13.5, *)) {
		[player fetchItemsForIdentityVerificationSignature:verificationSignatureHandler];
	} else {
		[player generateIdentityVerificationSignatureWithCompletionHandler:verificationSignatureHandler];
	}

	return OK;
};

void GameCenter::push_pending_event(Variant p_event) {
	pending_events.push_back(p_event);
}

void GameCenter::register_saved_games_listener() {
	if (gc_saved_games_listener_registered) {
		return;
	}
	if (NSClassFromString(@"GKLocalPlayer") == nil) {
		return;
	}
	if (gc_saved_games_listener == nil) {
		gc_saved_games_listener = [[GodotGameCenterSavedGamesListener alloc] init];
	}
	[[GKLocalPlayer localPlayer] registerListener:gc_saved_games_listener];
	gc_saved_games_listener_registered = true;
}

Error GameCenter::fetch_saved_games() {
	if (NSClassFromString(@"GKLocalPlayer") == nil) {
		return ERR_UNAVAILABLE;
	}

	GKLocalPlayer *player = [GKLocalPlayer localPlayer];
	ERR_FAIL_COND_V(![player respondsToSelector:@selector(fetchSavedGamesWithCompletionHandler:)], ERR_UNAVAILABLE);

	[player fetchSavedGamesWithCompletionHandler:^(NSArray<GKSavedGame *> *games, NSError *error) {
		Dictionary ret;
		ret["type"] = "saved_games";
		if (error == nil) {
			ret["result"] = "ok";
			Array saved_games;
			for (GKSavedGame *game in games) {
				saved_games.push_back(gc_saved_game_to_dict(game));
			}
			ret["saved_games"] = saved_games;
		} else {
			ret["result"] = "error";
			ret["error_code"] = (int64_t)error.code;
			ret["error_description"] = [error.localizedDescription UTF8String];
		};

		pending_events.push_back(ret);
	}];

	return OK;
};

Error GameCenter::load_saved_game(String p_name) {
	if (NSClassFromString(@"GKLocalPlayer") == nil) {
		return ERR_UNAVAILABLE;
	}

	GKLocalPlayer *player = [GKLocalPlayer localPlayer];
	ERR_FAIL_COND_V(![player respondsToSelector:@selector(fetchSavedGamesWithCompletionHandler:)], ERR_UNAVAILABLE);

	NSString *name_str = [[NSString alloc] initWithUTF8String:p_name.utf8().get_data()];

	[player fetchSavedGamesWithCompletionHandler:^(NSArray<GKSavedGame *> *games, NSError *error) {
		if (error != nil) {
			Dictionary ret;
			ret["type"] = "saved_game_loaded";
			ret["name"] = gc_string_from_nsstring(name_str);
			ret["result"] = "error";
			ret["error_code"] = (int64_t)error.code;
			ret["error_description"] = [error.localizedDescription UTF8String];
			pending_events.push_back(ret);
			return;
		};

		GKSavedGame *match = nil;
		for (GKSavedGame *game in games) {
			if ([game.name isEqualToString:name_str]) {
				match = game;
				break;
			}
		};

		if (match == nil) {
			Dictionary ret;
			ret["type"] = "saved_game_loaded";
			ret["name"] = gc_string_from_nsstring(name_str);
			ret["result"] = "error";
			ret["error_description"] = "not found";
			pending_events.push_back(ret);
			return;
		};

		[match loadDataWithCompletionHandler:^(NSData *data, NSError *load_error) {
			Dictionary ret;
			ret["type"] = "saved_game_loaded";
			ret["name"] = gc_string_from_nsstring(name_str);
			if (load_error == nil && data != nil) {
				ret["result"] = "ok";
				ret["data"] = gc_packed_from_nsdata(data);
			} else {
				ret["result"] = "error";
				if (load_error != nil) {
					ret["error_code"] = (int64_t)load_error.code;
					ret["error_description"] = [load_error.localizedDescription UTF8String];
				} else {
					ret["error_description"] = "no data";
				}
			};
			pending_events.push_back(ret);
		}];
	}];

	return OK;
};

Error GameCenter::save_game_data(String p_name, PackedByteArray p_data) {
	if (NSClassFromString(@"GKLocalPlayer") == nil) {
		return ERR_UNAVAILABLE;
	}

	GKLocalPlayer *player = [GKLocalPlayer localPlayer];
	ERR_FAIL_COND_V(![player respondsToSelector:@selector(saveGameData:withName:completionHandler:)], ERR_UNAVAILABLE);

	NSString *name_str = [[NSString alloc] initWithUTF8String:p_name.utf8().get_data()];
	NSData *data = gc_nsdata_from_packed(p_data);

	[player saveGameData:data
				withName:name_str
	   completionHandler:^(GKSavedGame *saved_game, NSError *error) {
		   Dictionary ret;
		   ret["type"] = "saved_game_written";
		   ret["name"] = gc_string_from_nsstring(name_str);
		   if (error == nil) {
			   ret["result"] = "ok";
			   if (saved_game != nil) {
				   ret["device"] = gc_string_from_nsstring(saved_game.deviceName);
				   ret["modified"] = saved_game.modificationDate ? (int64_t)[saved_game.modificationDate timeIntervalSince1970] : (int64_t)0;
			   }
		   } else {
			   ret["result"] = "error";
			   ret["error_code"] = (int64_t)error.code;
			   ret["error_description"] = [error.localizedDescription UTF8String];
		   };

		   pending_events.push_back(ret);
	   }];

	return OK;
};

Error GameCenter::delete_saved_game(String p_name) {
	if (NSClassFromString(@"GKLocalPlayer") == nil) {
		return ERR_UNAVAILABLE;
	}

	GKLocalPlayer *player = [GKLocalPlayer localPlayer];
	ERR_FAIL_COND_V(![player respondsToSelector:@selector(deleteSavedGamesWithName:completionHandler:)], ERR_UNAVAILABLE);

	NSString *name_str = [[NSString alloc] initWithUTF8String:p_name.utf8().get_data()];

	[player deleteSavedGamesWithName:name_str
				  completionHandler:^(NSError *error) {
					  Dictionary ret;
					  ret["type"] = "saved_game_deleted";
					  ret["name"] = gc_string_from_nsstring(name_str);
					  if (error == nil) {
						  ret["result"] = "ok";
					  } else {
						  ret["result"] = "error";
						  ret["error_code"] = (int64_t)error.code;
						  ret["error_description"] = [error.localizedDescription UTF8String];
					  };

					  pending_events.push_back(ret);
				  }];

	return OK;
};

Error GameCenter::resolve_conflicting_saved_games(String p_name, PackedByteArray p_data) {
	if (NSClassFromString(@"GKLocalPlayer") == nil) {
		return ERR_UNAVAILABLE;
	}

	GKLocalPlayer *player = [GKLocalPlayer localPlayer];
	ERR_FAIL_COND_V(![player respondsToSelector:@selector(resolveConflictingSavedGames:withData:completionHandler:)], ERR_UNAVAILABLE);

	NSString *name_str = [[NSString alloc] initWithUTF8String:p_name.utf8().get_data()];
	NSArray<GKSavedGame *> *conflicts = gc_conflicting_games ? gc_conflicting_games[name_str] : nil;

	if (conflicts == nil || conflicts.count == 0) {
		Dictionary ret;
		ret["type"] = "saved_games_conflict_resolved";
		ret["name"] = gc_string_from_nsstring(name_str);
		ret["result"] = "error";
		ret["error_description"] = "no conflicting saved games pending for this name";
		pending_events.push_back(ret);
		return ERR_UNAVAILABLE;
	};

	NSData *data = gc_nsdata_from_packed(p_data);

	[player resolveConflictingSavedGames:conflicts
							   withData:data
					  completionHandler:^(NSArray<GKSavedGame *> *saved_games, NSError *error) {
						  Dictionary ret;
						  ret["type"] = "saved_games_conflict_resolved";
						  ret["name"] = gc_string_from_nsstring(name_str);
						  if (error == nil) {
							  ret["result"] = "ok";
						  } else {
							  ret["result"] = "error";
							  ret["error_code"] = (int64_t)error.code;
							  ret["error_description"] = [error.localizedDescription UTF8String];
						  };

						  pending_events.push_back(ret);
					  }];

	[gc_conflicting_games removeObjectForKey:name_str];

	return OK;
};

Error GameCenter::submit_score(String p_leaderboard_id, int p_score) {
	if (NSClassFromString(@"GKLeaderboard") == nil) {
		return ERR_UNAVAILABLE;
	}
	ERR_FAIL_COND_V(![GKLeaderboard respondsToSelector:@selector(submitScore:context:player:leaderboardIDs:completionHandler:)], ERR_UNAVAILABLE);

	NSString *leaderboard_id = [[NSString alloc] initWithUTF8String:p_leaderboard_id.utf8().get_data()];

	[GKLeaderboard submitScore:(NSInteger)p_score
					  context:0
					   player:[GKLocalPlayer localPlayer]
			   leaderboardIDs:@[ leaderboard_id ]
			completionHandler:^(NSError *error) {
				Dictionary ret;
				ret["type"] = "score_submitted";
				ret["leaderboard_id"] = gc_string_from_nsstring(leaderboard_id);
				if (error == nil) {
					ret["result"] = "ok";
				} else {
					ret["result"] = "error";
					ret["error_code"] = (int64_t)error.code;
					ret["error_description"] = [error.localizedDescription UTF8String];
				};

				pending_events.push_back(ret);
			}];

	return OK;
};

Error GameCenter::load_leaderboard_scores(String p_leaderboard_id, int p_start_rank, int p_count) {
	if (NSClassFromString(@"GKLeaderboard") == nil) {
		return ERR_UNAVAILABLE;
	}
	ERR_FAIL_COND_V(![GKLeaderboard respondsToSelector:@selector(loadLeaderboardsWithIDs:completionHandler:)], ERR_UNAVAILABLE);

	NSString *leaderboard_id = [[NSString alloc] initWithUTF8String:p_leaderboard_id.utf8().get_data()];

	// GKLeaderboard ranks are 1-based; the valid range length is 1..100.
	NSInteger start = p_start_rank < 1 ? 1 : (NSInteger)p_start_rank;
	NSInteger length = p_count < 1 ? 1 : (p_count > 100 ? 100 : (NSInteger)p_count);
	NSRange range = NSMakeRange((NSUInteger)start, (NSUInteger)length);

	GKLeaderboard *cached = gc_leaderboards ? gc_leaderboards[leaderboard_id] : nil;
	if (cached != nil) {
		gc_load_leaderboard_entries(cached, leaderboard_id, range);
		return OK;
	}

	[GKLeaderboard loadLeaderboardsWithIDs:@[ leaderboard_id ]
						completionHandler:^(NSArray<GKLeaderboard *> *leaderboards, NSError *error) {
							if (error != nil || leaderboards.count == 0) {
								Dictionary ret;
								ret["type"] = "leaderboard_scores";
								ret["leaderboard_id"] = gc_string_from_nsstring(leaderboard_id);
								ret["result"] = "error";
								if (error != nil) {
									ret["error_code"] = (int64_t)error.code;
									ret["error_description"] = [error.localizedDescription UTF8String];
								} else {
									ret["error_description"] = "leaderboard not found";
								}
								pending_events.push_back(ret);
								return;
							};

							GKLeaderboard *board = leaderboards.firstObject;
							if (gc_leaderboards == nil) {
								gc_leaderboards = [NSMutableDictionary dictionary];
							}
							gc_leaderboards[leaderboard_id] = board;

							gc_load_leaderboard_entries(board, leaderboard_id, range);
						}];

	return OK;
};

void GameCenter::game_center_closed() {
	Dictionary ret;
	ret["type"] = "show_game_center";
	ret["result"] = "ok";
	pending_events.push_back(ret);
}

int GameCenter::get_pending_event_count() {
	return pending_events.size();
};

Variant GameCenter::pop_pending_event() {
	Variant front = pending_events.front()->get();
	pending_events.pop_front();

	return front;
};

GameCenter *GameCenter::get_singleton() {
	return instance;
};

GameCenter::GameCenter() {
	ERR_FAIL_COND(instance != NULL);
	instance = this;
	authenticated = false;

	gameCenterDelegate = [[GodotGameCenterDelegate alloc] init];
};

GameCenter::~GameCenter() {
	if (gameCenterDelegate) {
		gameCenterDelegate = nil;
	}

	if (gc_saved_games_listener != nil) {
		if (NSClassFromString(@"GKLocalPlayer") != nil) {
			[[GKLocalPlayer localPlayer] unregisterListener:gc_saved_games_listener];
		}
		gc_saved_games_listener = nil;
	}
	gc_saved_games_listener_registered = false;
	gc_conflicting_games = nil;
	gc_leaderboards = nil;
}

// GKLocalPlayerListener that surfaces diverged versions of a saved game.
// player:hasConflictingSavedGames: hands us every version across every
// conflicting name; we group by name, load the bytes of each version, and
// push one "saved_game_conflict" event per name once its versions are in.
@implementation GodotGameCenterSavedGamesListener

- (void)player:(GKPlayer *)player hasConflictingSavedGames:(NSArray<GKSavedGame *> *)savedGames {
	NSMutableDictionary<NSString *, NSMutableArray<GKSavedGame *> *> *by_name = [NSMutableDictionary dictionary];
	for (GKSavedGame *game in savedGames) {
		NSString *name = game.name ? game.name : @"";
		NSMutableArray<GKSavedGame *> *group = by_name[name];
		if (group == nil) {
			group = [NSMutableArray array];
			by_name[name] = group;
		}
		[group addObject:game];
	}

	if (gc_conflicting_games == nil) {
		gc_conflicting_games = [NSMutableDictionary dictionary];
	}

	for (NSString *name in by_name) {
		NSArray<GKSavedGame *> *group = [by_name[name] copy];
		gc_conflicting_games[name] = group;

		NSUInteger count = group.count;
		NSMutableArray *blobs = [NSMutableArray arrayWithCapacity:count];
		for (NSUInteger i = 0; i < count; i++) {
			[blobs addObject:[NSNull null]];
		}

		dispatch_group_t load_group = dispatch_group_create();
		NSLock *blobs_lock = [[NSLock alloc] init];
		__block bool any_error = false;

		for (NSUInteger i = 0; i < count; i++) {
			dispatch_group_enter(load_group);
			[group[i] loadDataWithCompletionHandler:^(NSData *data, NSError *error) {
				if (data != nil && error == nil) {
					[blobs_lock lock];
					blobs[i] = data;
					[blobs_lock unlock];
				} else {
					any_error = true;
				}
				dispatch_group_leave(load_group);
			}];
		}

		NSString *name_copy = [name copy];
		dispatch_group_notify(load_group, dispatch_get_main_queue(), ^{
			Dictionary ret;
			ret["type"] = "saved_game_conflict";
			ret["name"] = gc_string_from_nsstring(name_copy);

			Array versions;
			for (NSData *blob in blobs) {
				if ([blob isKindOfClass:[NSData class]]) {
					versions.push_back(gc_packed_from_nsdata(blob));
				}
			}
			ret["versions"] = versions;
			ret["result"] = any_error ? "error" : "ok";
			if (any_error) {
				ret["error_description"] = "failed to load one or more conflicting versions";
			}

			if (GameCenter::get_singleton()) {
				GameCenter::get_singleton()->push_pending_event(ret);
			}
		});
	}
}

@end
