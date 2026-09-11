# Godot iOS Keychain plugin

Added by the Crystal Tempest fork. Stores small byte values as generic-password
Keychain items, which (unlike the app's files) are normally kept when the app
is deleted. Godot 4 only. Engine singleton: `Keychain`.

An item is addressed by a **group** and a **key**:

- `kSecAttrService` = `<bundle id>.<group>`
- `kSecAttrAccount` = the key
- value = raw bytes

Items are written `kSecAttrAccessibleAfterFirstUnlock`, not a `ThisDeviceOnly`
class, so an encrypted device backup carries them to a new device. They are
never synchronizable (no iCloud Keychain). No entitlement is needed.

Apple does not promise that Keychain items survive deleting the app. Treat a
missing item as normal.

## Methods

Every call is synchronous; there are no events.

`read_item(String group, String key)` - Returns the stored `PackedByteArray`,
or `null` when there is no such item or the Keychain refused the read (see
`get_last_status()`). An item holding zero bytes returns an empty array, not
`null`.
`write_item(String group, String key, PackedByteArray value)` - Updates the
item, or adds it if it does not exist. Returns `OK` or `FAILED`.
`delete_item(String group, String key)` - Returns `OK` once the item is gone,
including when there was none.
`get_last_status()` - The `OSStatus` of the last call: `0` success, `-25300`
item not found, `-25308` interaction not allowed (the device has not been
unlocked since it started).
`get_plugin_version()` - The fork's git revision this plugin was built from;
`+` marks a build from a dirty tree.

## Building

```
./scripts/generate_xcframework.sh keychain release 4.0
./scripts/generate_xcframework.sh keychain release_debug 4.0
```

Copy `keychain.gdip` next to the two xcframeworks, renaming
`keychain.release_debug.xcframework` to `keychain.debug.xcframework`.
