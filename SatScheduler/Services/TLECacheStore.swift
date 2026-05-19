//
//  TLECacheStore.swift
//  SatScheduler
//

import Foundation

actor TLECacheStore {
	static let shared = TLECacheStore()

	private struct CacheFile: Codable {
		var entriesBySatelliteID: [String: CachedTLEEntry] = [:]
	}

	private struct CachedTLEEntry: Codable {
		let entry: TLEEntry
		let fetchedAt: Date

		func isFresh(now: Date, maxAge: TimeInterval) -> Bool {
			now.timeIntervalSince(fetchedAt) < maxAge
		}
	}

	private let dbService = SatNOGSDBService()
	private let defaultMaxAge: TimeInterval = 60 * 60
	private let cacheURL: URL

	private init() {
		let cachesDirectory = FileManager.default.urls(
			for: .cachesDirectory,
			in: .userDomainMask
		)[0]

		cacheURL = cachesDirectory.appendingPathComponent("tle_cache.json")
	}

	func fetchLatestTLEs(
		satelliteIDs: [String],
		maxCacheAge: TimeInterval? = nil,
		forceRefresh: Bool = false
	) async throws -> [TLEEntry] {
		let uniqueSatelliteIDs = Array(Set(satelliteIDs))
		guard !uniqueSatelliteIDs.isEmpty else {
			return []
		}

		let maxAge = maxCacheAge ?? defaultMaxAge
		let now = Date()
		var cache = loadCache()

		var resultsBySatelliteID: [String: TLEEntry] = [:]
		var satelliteIDsToFetch: [String] = []

		for satelliteID in uniqueSatelliteIDs {
			if !forceRefresh,
			   let cached = cache.entriesBySatelliteID[satelliteID],
			   cached.isFresh(now: now, maxAge: maxAge) {
				resultsBySatelliteID[satelliteID] = cached.entry
			} else {
				satelliteIDsToFetch.append(satelliteID)
			}
		}

		if !satelliteIDsToFetch.isEmpty {
			let fetchedEntries = try await dbService.fetchLatestTLEs(
				satelliteIDs: satelliteIDsToFetch
			)

			for entry in fetchedEntries {
				let satelliteID = entry.sat_id
				cache.entriesBySatelliteID[satelliteID] = CachedTLEEntry(
					entry: entry,
					fetchedAt: now
				)
				resultsBySatelliteID[satelliteID] = entry
			}

			save(cache)
		}

		return uniqueSatelliteIDs.compactMap { resultsBySatelliteID[$0] }
	}

	func fetchLatestTLE(
		satelliteID: String,
		maxCacheAge: TimeInterval? = nil,
		forceRefresh: Bool = false
	) async throws -> TLEEntry? {
		try await fetchLatestTLEs(
			satelliteIDs: [satelliteID],
			maxCacheAge: maxCacheAge,
			forceRefresh: forceRefresh
		).first
	}

	func invalidate(satelliteIDs: [String]) {
		var cache = loadCache()
		for satelliteID in satelliteIDs {
			cache.entriesBySatelliteID.removeValue(forKey: satelliteID)
		}
		save(cache)
	}

	func clear() {
		save(CacheFile())
	}

	private func loadCache() -> CacheFile {
		guard let data = try? Data(contentsOf: cacheURL) else {
			return CacheFile()
		}

		let decoder = JSONDecoder()
		decoder.dateDecodingStrategy = .iso8601

		return (try? decoder.decode(CacheFile.self, from: data)) ?? CacheFile()
	}

	private func save(_ cache: CacheFile) {
		let encoder = JSONEncoder()
		encoder.dateEncodingStrategy = .iso8601

		guard let data = try? encoder.encode(cache) else {
			return
		}

		try? data.write(to: cacheURL, options: [.atomic])
	}
}
