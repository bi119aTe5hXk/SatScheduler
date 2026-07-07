//
//  ObservationsStore.swift
//  SatScheduler
//
//  Created by bi119aTe5hXk on 2026/05/18.
//
import Foundation

final class ObservationsStore {

	static let shared = ObservationsStore()

	struct UnknownObservationsCache: Codable {
		var observations: [Observation]
		var nextCursor: String?
		var updatedAt: Date

		var canLoadMore: Bool {
			nextCursor != nil
		}
	}

	private let keyPrefix = "satnogs.cachedUnknownObservations"
	private let cachesDirectory: URL

	private init() {
		cachesDirectory = FileManager.default.urls(
			for: .cachesDirectory,
			in: .userDomainMask
		)[0]
	}

	func loadUnknownObservations(observerID: Int) -> [Observation] {
		loadUnknownObservationsCache(observerID: observerID).observations
	}

	func loadUnknownObservationsCache(observerID: Int) -> UnknownObservationsCache {
		if let cache = loadFileCache(observerID: observerID) {
			return cache
		}

		let key = cacheKey(observerID: observerID)
		guard let data = UserDefaults.standard.data(forKey: key) else {
			return UnknownObservationsCache(
				observations: [],
				nextCursor: nil,
				updatedAt: Date.distantPast
			)
		}

		do {
			let observations = try JSONDecoder().decode([Observation].self, from: data)
			let cache = UnknownObservationsCache(
				observations: observations,
				nextCursor: nil,
				updatedAt: Date()
			)
			saveUnknownObservationsCache(cache, observerID: observerID)
			UserDefaults.standard.removeObject(forKey: key)
			return cache
		} catch {
			print("Failed to decode cached observations for observer \(observerID): \(error.localizedDescription)")
			return UnknownObservationsCache(
				observations: [],
				nextCursor: nil,
				updatedAt: Date.distantPast
			)
		}
	}

	func saveUnknownObservations(_ observations: [Observation], observerID: Int) {
		saveUnknownObservationsCache(
			UnknownObservationsCache(
				observations: observations,
				nextCursor: nil,
				updatedAt: Date()
			),
			observerID: observerID
		)
	}

	func saveUnknownObservationsCache(_ cache: UnknownObservationsCache, observerID: Int) {
		let encoder = JSONEncoder()
		encoder.dateEncodingStrategy = .iso8601

		do {
			let data = try encoder.encode(cache)
			try data.write(to: cacheURL(observerID: observerID), options: [.atomic])
		} catch {
			print("Failed to encode cached observations for observer \(observerID): \(error.localizedDescription)")
		}
	}

	func clearUnknownObservations(observerID: Int) {
		try? FileManager.default.removeItem(at: cacheURL(observerID: observerID))
		UserDefaults.standard.removeObject(forKey: cacheKey(observerID: observerID))
	}

	private func loadFileCache(observerID: Int) -> UnknownObservationsCache? {
		guard let data = try? Data(contentsOf: cacheURL(observerID: observerID)) else {
			return nil
		}

		let decoder = JSONDecoder()
		decoder.dateDecodingStrategy = .iso8601

		do {
			return try decoder.decode(UnknownObservationsCache.self, from: data)
		} catch {
			print("Failed to decode cached observations for observer \(observerID): \(error.localizedDescription)")
			return nil
		}
	}

	private func cacheURL(observerID: Int) -> URL {
		cachesDirectory.appendingPathComponent("unknown_observations_\(observerID).json")
	}

	private func cacheKey(observerID: Int) -> String {
		"\(keyPrefix).\(observerID)"
	}
}
