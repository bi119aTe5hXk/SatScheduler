//
//  StationScheduleStore.swift
//  SatScheduler
//
//  Created by bi119aTe5hXk on 2026/05/16.
//

import Foundation
final class StationScheduleStore {
	static let shared = StationScheduleStore()

	private let cacheKey = "SatScheduler.stationScheduleCache"
	private let networkService = SatNOGSNetworkService()

	private init() {}

	func loadCachedSchedule() -> StationScheduleCache {
		guard let data = UserDefaults.standard.data(forKey: cacheKey) else {
			return StationScheduleCache(updatedAt: nil, stationSchedules: [])
		}

		do {
			let decoder = JSONDecoder()
			decoder.dateDecodingStrategy = .iso8601
			return try decoder.decode(StationScheduleCache.self, from: data)
		} catch {
			return StationScheduleCache(updatedAt: nil, stationSchedules: [])
		}
	}

	@discardableResult
	func refreshSchedule(
		start: Date,
		end: Date,
		groundStationIDs: [Int]
	) async throws -> StationScheduleCache {
		let observations = try await networkService.fetchScheduledObservations(
			start: start,
			end: end,
			groundStationIDs: groundStationIDs
		)
		let refreshedCache = buildCache(from: observations)
		let cache = mergedCache(
			refreshedCache: refreshedCache,
			refreshedStationIDs: Set(groundStationIDs)
		)
		save(cache)
		return cache
	}

	@discardableResult
	func replaceSchedule(with observations: [Observation]) -> StationScheduleCache {
		let refreshedCache = buildCache(from: observations)
		let refreshedStationIDs = Set(refreshedCache.stationSchedules.map(\.stationID))
		let cache = mergedCache(
			refreshedCache: refreshedCache,
			refreshedStationIDs: refreshedStationIDs
		)
		save(cache)
		return cache
	}

	@discardableResult
	func replaceSchedule(
		with observations: [Observation],
		groundStationIDs: [Int]
	) -> StationScheduleCache {
		let refreshedCache = buildCache(from: observations)
		let cache = mergedCache(
			refreshedCache: refreshedCache,
			refreshedStationIDs: Set(groundStationIDs)
		)
		save(cache)
		return cache
	}

	func mergeCreatedObservations(_ observations: [Observation]) {
		let current = loadCachedSchedule()
		let mapped = observations.compactMap(Self.makeScheduleObservation)

		let existing = current.stationSchedules.flatMap(\.observations)
		let merged = Dictionary(grouping: existing + mapped, by: { $0.stationID })
		let timelines = merged.map { stationID, observations in
			let sortedObservations = observations
				.reduce(into: [Int: StationScheduleObservation]()) { result, observation in
					result[observation.id] = observation
				}
				.values
				.sorted { $0.start < $1.start }

			return StationScheduleTimeline(
				stationID: stationID,
				stationName: sortedObservations.first?.stationName ?? "Station \(stationID)",
				observations: sortedObservations
			)
		}
		.sorted { $0.displayName < $1.displayName }

		save(StationScheduleCache(updatedAt: Date(), stationSchedules: timelines))
	}

	private static func makeScheduleObservation(from observation: Observation) -> StationScheduleObservation? {
		guard let stationID = observation.ground_station,
			  let startString = observation.start,
			  let endString = observation.end,
			  let start = parseObservationDate(startString),
			  let end = parseObservationDate(endString) else {
			return nil
		}

		let observationID = observation.id
		let stationName = observation.station_name ?? "Station \(stationID)"
		let tle0DisplayName = observation.tle0?
			.replacingOccurrences(of: "^0\\s+", with: "", options: .regularExpression)
			.trimmingCharacters(in: .whitespacesAndNewlines)

		let satelliteName = observation.satellite_name?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
			?? tle0DisplayName?.nilIfEmpty
			?? observation.norad_cat_id.map { "NORAD \($0)" }
			?? "Observation \(observationID)"
		let transmitterDescription = observation.transmitter_description ?? observation.transmitter_uuid ?? observation.transmitter ?? ""
		let tle0 = observation.tle0

		return StationScheduleObservation(
			id: observationID,
			stationID: stationID,
			stationName: stationName,
			satelliteName: satelliteName,
			tle0: tle0,
			transmitterDescription: transmitterDescription,
			start: start,
			end: end
		)
	}

	private static func parseObservationDate(_ string: String) -> Date? {
		if let date = SatNOGSNetworkService.observationDateFormatter.date(from: string) {
			return date
		}

		if let date = SatNOGSNetworkService.isoFormatter.date(from: string) {
			return date
		}

		let fallbackFormatter = DateFormatter()
		fallbackFormatter.locale = Locale(identifier: "en_US_POSIX")
		fallbackFormatter.timeZone = TimeZone(secondsFromGMT: 0)
		fallbackFormatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ssXXXXX"
		return fallbackFormatter.date(from: string)
	}

	private func buildCache(from observations: [Observation]) -> StationScheduleCache {
		let mapped = observations.compactMap(Self.makeScheduleObservation)

		let timelines = Dictionary(grouping: mapped, by: { $0.stationID })
			.map { stationID, observations in
				StationScheduleTimeline(
					stationID: stationID,
					stationName: observations.first?.stationName ?? "Station \(stationID)",
					observations: observations.sorted { $0.start < $1.start }
				)
			}
			.sorted { $0.displayName < $1.displayName }

		return StationScheduleCache(updatedAt: Date(), stationSchedules: timelines)
	}

	private func mergedCache(
		refreshedCache: StationScheduleCache,
		refreshedStationIDs: Set<Int>
	) -> StationScheduleCache {
		let current = loadCachedSchedule()
		let mergedTimelines = current.stationSchedules
			.filter { !refreshedStationIDs.contains($0.stationID) } + refreshedCache.stationSchedules

		return StationScheduleCache(
			updatedAt: Date(),
			stationSchedules: mergedTimelines.sorted { $0.displayName < $1.displayName }
		)
	}

	private func save(_ cache: StationScheduleCache) {
		do {
			let encoder = JSONEncoder()
			encoder.dateEncodingStrategy = .iso8601
			let data = try encoder.encode(cache)
			UserDefaults.standard.set(data, forKey: cacheKey)
		} catch {
			print("Failed to save station schedule cache: \(error)")
		}
	}
	func clearCache() {
		UserDefaults.standard.removeObject(forKey: cacheKey)
	}
}

private extension String {
	var nilIfEmpty: String? {
		isEmpty ? nil : self
	}
}
