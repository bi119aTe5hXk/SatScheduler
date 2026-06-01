//
//  WatchTargetStore.swift
//  SatScheduler
//
//  Created by bi119aTe5hXk on 2026/05/16.
//

import Foundation

final class WatchTargetStore {

	static let shared = WatchTargetStore()

	private init() {}

	private let store = NSUbiquitousKeyValueStore.default
	private let storageKey = "SatScheduler.watchTargets"

	func loadWatchTargets() -> [WatchTarget] {
		store.synchronize()

		guard let data = store.data(forKey: storageKey) else {
			return []
		}

		do {
			return try JSONDecoder().decode([WatchTarget].self, from: data)
		} catch {
			print("Failed to decode watch targets from iCloud: \(error)")
			return []
		}
	}

	func saveWatchTargets(_ targets: [WatchTarget]) {
		do {
			let data = try JSONEncoder().encode(targets)
			store.set(data, forKey: storageKey)
			store.synchronize()
		} catch {
			print("Failed to encode watch targets for iCloud: \(error)")
		}
	}
	
	func replaceTargets(_ newTargets: [WatchTarget]) {
		saveWatchTargets(newTargets)
	}

	func deleteAll() {
		store.removeObject(forKey: storageKey)
		store.synchronize()
	}
}
