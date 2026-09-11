/*************************************************************************/
/*  keychain_module.cpp                                                  */
/*************************************************************************/
/* Crystal Tempest fork of godot-ios-plugins. MIT licensed, as the rest  */
/* of this repository.                                                   */
/*************************************************************************/

#include "keychain_module.h"

#include "core/config/engine.h"

#include "keychain.h"

Keychain *keychain;

void register_keychain_types() {
	keychain = memnew(Keychain);
	Engine::get_singleton()->add_singleton(Engine::Singleton("Keychain", keychain));
}

void unregister_keychain_types() {
	if (keychain) {
		memdelete(keychain);
	}
}
