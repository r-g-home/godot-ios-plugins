# Godot iOS iCloud plugin

Plugin generates new event with `key_value_changed` type when values stored in the iCloud key-value store changes.  

## Methods

`remove_key(String key)` - Removes the value associated with the specified key from the iCloud key-value store.  
`set_key_values(Dictionary values)` - Sets multiple objects for the specified keys in the iCloud key-value store.  
`get_key_value(String key)` - Returns the object associated with the specified key stored in iCloud key-value store.  
`synchronize_key_values()` - Synchronizes in-memory keys and values for iCloud storage with those stored on disk.  
`get_all_key_values()` - Returns a dictionary containing all of the key-value pairs in the iCloud key-value store.  

Added by the Crystal Tempest fork:

`get_account_id()` - An opaque, stable id for the iCloud account signed in on this device, or `""` when there is none. Each account seen on the device gets a random id, stored in the Keychain (service `<bundle id>.icloud-account`, account = the id) together with the archived `NSFileManager.ubiquityIdentityToken`; the current token is matched against the stored ones with `isEqual:`, as Apple intends, never by its bytes. So the id survives relaunches, reinstalls (as far as the Keychain does) and changes in how the token archives. Also `""` while the Keychain cannot be used (the device not unlocked since it started), rather than an id that could not be found again. Never shown or sent anywhere; it need not match across devices.  
`get_plugin_version()` - The fork's git revision this plugin was built from; `+` marks a build from a dirty tree.  

The key-value store needs the `com.apple.developer.ubiquity-kvstore-identifier` entitlement.

## Properties

## Events reporting

`get_pending_event_count()` - Returns number of events pending from plugin to be processed.  
`pop_pending_event()` - Returns first unprocessed plugin event, or `null` when there is none.  

Events:

- `key_value_changed` - `reason` (`server`, `initial_sync`, `quota_violation`, `account`) and `changed_values` (key -> new value; a `PackedByteArray` for data values).
- `account_changed` (fork) - the iCloud account on the device changed (`NSUbiquityIdentityDidChangeNotification`); `account_id` is the new `get_account_id()`.

Events are queued on the main thread (the fork moved both notification observers onto the main queue; the stock plugin pushed from a background thread).