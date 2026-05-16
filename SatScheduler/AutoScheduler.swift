//
//  AutoScheduler.swift
//  SatScheduler
//
//  Created by bi119aTe5hXk on 2026/05/16.
//

import Foundation
import SatelliteKit

final class AutoScheduler {

	private let networkService: SatNOGSNetworkService
	private let dbService: SatNOGSDBService
	private let passPredictor: PassPredictor

	init(
		networkService: SatNOGSNetworkService = SatNOGSNetworkService(),
		dbService: SatNOGSDBService = SatNOGSDBService(),
		passPredictor: PassPredictor = PassPredictor()
	) {
		self.networkService = networkService
		self.dbService = dbService
		self.passPredictor = passPredictor
	}

	func schedule(
		target: WatchTarget,
		from start: Date,
		to end: Date
	) async throws -> [Observation] {
		guard let tle = try await dbService.fetchLatestTLE(satelliteID: target.satelliteID) else {
			throw AutoSchedulerError.tleNotFound(target.satelliteID)
		}

		let stations = try await resolveStations(for: target)
		let requests = try stations.flatMap { station in
			try makeScheduleRequests(
				target: target,
				tle: tle,
				station: station,
				start: start,
				end: end
			)
		}

		guard !requests.isEmpty else {
			return []
		}

		let stationIDs = Array(Set(requests.map { request in
			request.groundStationID
		})).sorted()
		let requestStart = requests.map { request in
			request.start
		}.min() ?? start
		let requestEnd = requests.map { request in
			request.end
		}.max() ?? end

		let existingObservations = try await networkService.fetchScheduledObservations(
			start: requestStart,
			end: requestEnd,
			groundStationIDs: stationIDs
		)

		let conflictResult = ObservationScheduleConflictResolver.filterConflicts(
			requests: requests,
			existingObservations: existingObservations,
			conflictBuffer: 5 * 60
		)

		guard !conflictResult.allowedRequests.isEmpty else {
			print("Auto schedule skipped: all \(conflictResult.skippedRequests.count) request(s) overlap with existing observations.")
			return []
		}

		let observations = try await networkService.createObservations(conflictResult.allowedRequests)
		print("Auto schedule created \(observations.count) observation(s), skipped \(conflictResult.skippedRequests.count) conflicting request(s).")
		return observations
	}

	private func makeScheduleRequests(
		target: WatchTarget,
		tle: TLEEntry,
		station: WatchStationSnapshot,
		start: Date,
		end: Date
	) throws -> [ObservationScheduleRequest] {
		let minimumElevation = max(
			0,
			target.minElevation ?? 0,
			station.minHorizon ?? 0
		)

		let passWindows = try passPredictor.predictPasses(
			tleName: tle.tle0,
			tleLine1: tle.tle1,
			tleLine2: tle.tle2,
			station: station,
			from: start,
			to: end,
			minimumElevation: minimumElevation
		)

		return passWindows.map { passWindow in
			ObservationScheduleRequest(
				groundStationID: station.id,
				transmitterUUID: target.transmitterID,
				start: passWindow.start,
				end: passWindow.end
			)
		}
	}

	private func resolveStations(for target: WatchTarget) async throws -> [WatchStationSnapshot] {
		let snapshotByID = target.stationSnapshots ?? [:]
		let cachedSnapshots = target.stationIDs.compactMap { snapshotByID[$0] }

		if cachedSnapshots.count == target.stationIDs.count {
			return cachedSnapshots
		}

		let fetchedStations = try await networkService.fetchOnlineStations()
		let fetchedSnapshotsByID = Dictionary(
			uniqueKeysWithValues: fetchedStations.map { station in
				(
					station.id,
					WatchStationSnapshot(
						id: station.id,
						name: station.name ?? "Station \(station.id)",
						latitude: station.lat,
						longitude: station.lng,
						altitude: station.altitude,
						minHorizon: station.min_horizon
					)
				)
			}
		)

		guard !fetchedSnapshotsByID.isEmpty || !snapshotByID.isEmpty else {
			throw AutoSchedulerError.stationSnapshotNotFound
		}

		return target.stationIDs.compactMap { stationID in
			if let snapshot = snapshotByID[stationID] {
				return snapshot
			}

			return fetchedSnapshotsByID[stationID]
		}
	}
}

enum AutoSchedulerError: LocalizedError {
	case tleNotFound(String)
	case stationSnapshotNotFound

	var errorDescription: String? {
		switch self {
		case .tleNotFound(let satelliteID):
			return "TLE not found for satellite \(satelliteID)."
		case .stationSnapshotNotFound:
			return "Station snapshot not found. Please refresh the watch target stations."
		}
	}
}
