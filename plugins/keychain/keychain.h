/*************************************************************************/
/*  keychain.h                                                           */
/*************************************************************************/
/* Crystal Tempest fork of godot-ios-plugins. MIT licensed, as the rest  */
/* of this repository.                                                   */
/*************************************************************************/

#ifndef KEYCHAIN_H
#define KEYCHAIN_H

#include "core/object/class_db.h"

// Generic-password Keychain items.
//
// An item is addressed by a group and a key: kSecAttrService is
// "<bundle id>.<group>", kSecAttrAccount is the key, and the value is raw
// bytes. Items are written kSecAttrAccessibleAfterFirstUnlock - not a
// ThisDeviceOnly class, so an encrypted device backup carries them to a new
// device - and are never synchronizable (no iCloud Keychain).
//
// Every call is synchronous and answers before it returns: these are fast
// local lookups, so there is no event queue.
//
// Godot 4 only.
class Keychain : public Object {
	GDCLASS(Keychain, Object);

	static Keychain *instance;
	static void _bind_methods();

	int last_status = 0;

public:
	// The stored bytes, or null when there is no such item - or when the
	// Keychain refused the read, which get_last_status() tells apart. An item
	// holding zero bytes reads back as an empty PackedByteArray, not null.
	Variant read_item(String p_group, String p_key);

	// Updates the item if it exists, adds it if not. OK or FAILED.
	Error write_item(String p_group, String p_key, PackedByteArray p_value);

	// OK once the item is gone, including when there was none.
	Error delete_item(String p_group, String p_key);

	// The OSStatus of the last call: 0 errSecSuccess, -25300
	// errSecItemNotFound, -25308 errSecInteractionNotAllowed (the device has
	// not been unlocked since it started), ...
	int get_last_status();

	// The fork's git revision this plugin was built from ("+" = dirty tree).
	String get_plugin_version();

	static Keychain *get_singleton();

	Keychain();
	~Keychain();
};

#endif
