/*************************************************************************/
/*  keychain.mm                                                          */
/*************************************************************************/
/* Crystal Tempest fork of godot-ios-plugins. MIT licensed, as the rest  */
/* of this repository.                                                   */
/*************************************************************************/

#include "keychain.h"

#import <Foundation/Foundation.h>
#import <Security/Security.h>

// Stamped by SConstruct from the fork's git revision.
#ifndef KEYCHAIN_PLUGIN_VERSION
#define KEYCHAIN_PLUGIN_VERSION "unknown"
#endif

Keychain *Keychain::instance = NULL;

static NSString *kc_nsstring(const String &p_string) {
	return [NSString stringWithUTF8String:p_string.utf8().get_data()];
}

// The attributes that identify one item: service "<bundle id>.<group>",
// account = key. Leaving kSecAttrSynchronizable out means only
// non-synchronizable items are matched and added.
static NSMutableDictionary *kc_item_query(const String &p_group, const String &p_key) {
	NSString *bundle_id = [[NSBundle mainBundle] bundleIdentifier] ?: @"godot";
	NSMutableDictionary *query = [NSMutableDictionary dictionary];
	query[(__bridge id)kSecClass] = (__bridge id)kSecClassGenericPassword;
	query[(__bridge id)kSecAttrService] = [NSString stringWithFormat:@"%@.%@", bundle_id, kc_nsstring(p_group)];
	query[(__bridge id)kSecAttrAccount] = kc_nsstring(p_key);
	return query;
}

void Keychain::_bind_methods() {
	ClassDB::bind_method(D_METHOD("read_item", "group", "key"), &Keychain::read_item);
	ClassDB::bind_method(D_METHOD("write_item", "group", "key", "value"), &Keychain::write_item);
	ClassDB::bind_method(D_METHOD("delete_item", "group", "key"), &Keychain::delete_item);
	ClassDB::bind_method(D_METHOD("get_last_status"), &Keychain::get_last_status);
	ClassDB::bind_method(D_METHOD("get_plugin_version"), &Keychain::get_plugin_version);
}

Variant Keychain::read_item(String p_group, String p_key) {
	NSMutableDictionary *query = kc_item_query(p_group, p_key);
	query[(__bridge id)kSecReturnData] = @YES;
	query[(__bridge id)kSecMatchLimit] = (__bridge id)kSecMatchLimitOne;

	CFTypeRef result = NULL;
	OSStatus status = SecItemCopyMatching((__bridge CFDictionaryRef)query, &result);
	last_status = (int)status;
	if (status != errSecSuccess || result == NULL) {
		return Variant();
	}

	NSData *data = (__bridge_transfer NSData *)result;
	PackedByteArray bytes;
	bytes.resize((int)data.length);
	if (data.length > 0) {
		memcpy(bytes.ptrw(), data.bytes, data.length);
	}
	return bytes;
}

Error Keychain::write_item(String p_group, String p_key, PackedByteArray p_value) {
	NSMutableDictionary *query = kc_item_query(p_group, p_key);
	NSData *data = [NSData dataWithBytes:p_value.ptr() length:p_value.size()];
	NSDictionary *attributes = @{
		(__bridge id)kSecValueData : data,
		(__bridge id)kSecAttrAccessible : (__bridge id)kSecAttrAccessibleAfterFirstUnlock,
	};

	OSStatus status = SecItemUpdate((__bridge CFDictionaryRef)query, (__bridge CFDictionaryRef)attributes);
	if (status == errSecItemNotFound) {
		[query addEntriesFromDictionary:attributes];
		status = SecItemAdd((__bridge CFDictionaryRef)query, NULL);
	}
	last_status = (int)status;
	return status == errSecSuccess ? OK : FAILED;
}

Error Keychain::delete_item(String p_group, String p_key) {
	OSStatus status = SecItemDelete((__bridge CFDictionaryRef)kc_item_query(p_group, p_key));
	last_status = (int)status;
	return (status == errSecSuccess || status == errSecItemNotFound) ? OK : FAILED;
}

int Keychain::get_last_status() {
	return last_status;
}

String Keychain::get_plugin_version() {
	return String(KEYCHAIN_PLUGIN_VERSION);
}

Keychain *Keychain::get_singleton() {
	return instance;
}

Keychain::Keychain() {
	ERR_FAIL_COND(instance != NULL);
	instance = this;
}

Keychain::~Keychain() {
	if (instance == this) {
		instance = NULL;
	}
}
