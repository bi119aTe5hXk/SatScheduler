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
	
	func scheduleTargets(
		_ targets: [WatchTarget],
		from start: Date,
		to end: Date,
		delayBetweenTargets: TimeInterval = 1,
		shouldCancel: (@MainActor () -> Bool)? = nil,
		onProgress: (@MainActor (AutoScheduleTargetResult) -> Void)? = nil
	) async -> AutoScheduleBatchResult {
		var targetResults: [AutoScheduleTargetResult] = []
		var allCreatedObservations: [Observation] = []
		var cachedExistingObservations: [Observation] = []

		do {
			let stationIDs = Array(Set(targets.flatMap { target in
				target.stationIDs
			})).sorted()

			if !stationIDs.isEmpty {
				cachedExistingObservations = try await networkService.fetchScheduledObservations(
					start: start,
					end: end,
					groundStationIDs: stationIDs
				)
			}
		} catch {
			print("Auto schedule warning: failed to preload station schedules: \(error.localizedDescription)")
		}

		for (index, target) in targets.enumerated() {
			if await shouldCancel?() == true {
				break
			}

			let targetResult: AutoScheduleTargetResult

			do {
				let observations = try await schedule(
					target: target,
					from: start,
					to: end,
					existingObservations: cachedExistingObservations
				)

				allCreatedObservations.append(contentsOf: observations)
				cachedExistingObservations.append(contentsOf: observations)
				targetResult = AutoScheduleTargetResult(
					target: target,
					status: .success(createdCount: observations.count)
				)
			} catch {
				targetResult = AutoScheduleTargetResult(
					target: target,
					status: .failure(message: error.localizedDescription)
				)

				print("Auto schedule failed for target \(target.satelliteID): \(error.localizedDescription)")
			}

			targetResults.append(targetResult)
			await onProgress?(targetResult)

			if index < targets.count - 1, delayBetweenTargets > 0 {
				let delayStep: TimeInterval = 0.25
				var delayed: TimeInterval = 0

				while delayed < delayBetweenTargets {
					if await shouldCancel?() == true {
						break
					}

					let nextStep = min(delayStep, delayBetweenTargets - delayed)
					try? await Task.sleep(nanoseconds: UInt64(nextStep * 1_000_000_000))
					delayed += nextStep
				}
			}
		}

		return AutoScheduleBatchResult(
			results: targetResults,
			createdObservations: allCreatedObservations
		)
	}

	func schedule(
		target: WatchTarget,
		from start: Date,
		to end: Date
	) async throws -> [Observation] {
		try await schedule(
			target: target,
			from: start,
			to: end,
			existingObservations: nil
		)
	}

	private func schedule(
		target: WatchTarget,
		from start: Date,
		to end: Date,
		existingObservations preloadedExistingObservations: [Observation]?
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

		let existingObservations: [Observation]
		if let preloadedExistingObservations {
			existingObservations = preloadedExistingObservations
		} else {
			existingObservations = try await networkService.fetchScheduledObservations(
				start: requestStart,
				end: requestEnd,
				groundStationIDs: stationIDs
			)
		}

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

struct AutoScheduleBatchResult {
	let results: [AutoScheduleTargetResult]
	let createdObservations: [Observation]

	var successResults: [AutoScheduleTargetResult] {
		results.filter { result in
			if case .success(let createdCount) = result.status {
				return createdCount > 0
			}
			return false
		}

	}

	var skippedResults: [AutoScheduleTargetResult] {
		results.filter { result in
			if case .success(let createdCount) = result.status {
				return createdCount == 0
			}
			return false
		}

	}

	var failureResults: [AutoScheduleTargetResult] {
		results.filter { result in
			if case .failure = result.status {
				return true
			}

			return false
		}
	}

	var createdCount: Int {
		createdObservations.count
	}
}

struct AutoScheduleTargetResult: Identifiable {
	let target: WatchTarget
	let status: AutoScheduleTargetStatus

	var id: WatchTarget.ID {
		target.id
	}
}

enum AutoScheduleTargetStatus: Equatable {
	case success(createdCount: Int)
	case failure(message: String)

	var displayMessage: String {
		switch self {
		case .success(let createdCount):
			if createdCount == 0 {
				return "Skipped: no available observation windows."
			}
			return "Scheduled \(createdCount) observation(s)."
		case .failure(let message):
			return message
		}
	}
}
