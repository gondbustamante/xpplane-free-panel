import Observation

/// Dictionary whose entries are observed one by one. A view that reads `store[key]` only
/// redraws when that key changes, not when any other one does. With a plain observed
/// dictionary every switch, lamp and display of the overhead redrew on each dataref update
/// (latitude, altitude… several times a second in flight), which is what slowed the iPad down.
@MainActor
final class KeyedStore<Key: Hashable, Value: Equatable> {
    private var entries: [Key: ObservedEntry<Value>] = [:]

    /// Reading registers interest in this key only. Writing an equal value notifies no one.
    subscript(key: Key) -> Value? {
        get { entry(key).value }
        set {
            let entry = entry(key)
            if entry.value != newValue { entry.value = newValue }
        }
    }

    private func entry(_ key: Key) -> ObservedEntry<Value> {
        if let entry = entries[key] { return entry }
        let entry = ObservedEntry<Value>()
        entries[key] = entry
        return entry
    }
}

/// One observed value of a `KeyedStore`.
@MainActor
@Observable
final class ObservedEntry<Value> {
    var value: Value?
}
