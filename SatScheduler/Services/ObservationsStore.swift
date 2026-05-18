//
//  ObservationsStore.swift
//  SatScheduler
//
//  Created by bi119aTe5hXk on 2026/05/18.
//
import Foundation

final class ObservationsStore {

	static let shared = ObservationsStore()

	private let userDefaults: UserDefaults
	private let keyPrefix = "satnogs.cachedUnknownObservations"

	private init(userDefaults: UserDefaults = .standard) {
		self.userDefaults = userDefaults
	}

	func loadUnknownObservations(observerID: Int) -> [Observation] {
		let key = cacheKey(observerID: observerID)
		guard let data = userDefaults.data(forKey: key) else {
			return []
		}

		do {
			return try JSONDecoder().decode([Observation].self, from: data)
		} catch {
			print("Failed to decode cached observations for observer \(observerID): \(error.localizedDescription)")
			return []
		}
	}

	func saveUnknownObservations(_ observations: [Observation], observerID: Int) {
		let key = cacheKey(observerID: observerID)

		do {
			let data = try JSONEncoder().encode(observations)
			userDefaults.set(data, forKey: key)
		} catch {
			print("Failed to encode cached observations for observer \(observerID): \(error.localizedDescription)")
		}
	}

	func clearUnknownObservations(observerID: Int) {
		userDefaults.removeObject(forKey: cacheKey(observerID: observerID))
	}

	private func cacheKey(observerID: Int) -> String {
		"\(keyPrefix).\(observerID)"
	}
}
