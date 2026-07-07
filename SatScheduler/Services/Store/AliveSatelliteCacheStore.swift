//
//  AliveSatelliteCacheStore.swift
//  SatScheduler
//

import Foundation

actor AliveSatelliteCacheStore {
	static let shared = AliveSatelliteCacheStore()

	private struct CacheFile: Codable {
		let satellites: [SatelliteModel]
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

		cacheURL = cachesDirectory.appendingPathComponent("alive_satellites_cache.json")
	}

	func fetchAliveSatellites(
		maxCacheAge: TimeInterval? = nil,
		forceRefresh: Bool = false
	) async throws -> [SatelliteModel] {
		let maxAge = maxCacheAge ?? defaultMaxAge
		let now = Date()

		if !forceRefresh,
		   let cache = loadCache(),
		   cache.isFresh(now: now, maxAge: maxAge) {
			return cache.satellites
		}

		let satellites = try await dbService.fetchAliveSatellites()
		save(CacheFile(satellites: satellites, fetchedAt: now))
		return satellites
	}

	func clear() {
		try? FileManager.default.removeItem(at: cacheURL)
	}

	private func loadCache() -> CacheFile? {
		guard let data = try? Data(contentsOf: cacheURL) else {
			return nil
		}

		let decoder = JSONDecoder()
		decoder.dateDecodingStrategy = .iso8601

		return try? decoder.decode(CacheFile.self, from: data)
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
