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

	init(
		networkService: SatNOGSNetworkService = SatNOGSNetworkService()
	) {
		self.networkService = networkService
	}

	func schedulePlan(
		_ plan: AutoSchedulePlan,
		delayBetweenRequests: TimeInterval = 0,
		shouldCancel: (@MainActor () -> Bool)? = nil,
		onProgress: (@MainActor (Int, Int) -> Void)? = nil
	) async throws -> [Observation] {
		var createdObservations: [Observation] = []
		let requests = plan.requests

		for (index, request) in requests.enumerated() {
			if await shouldCancel?() == true {
				break
			}

			let observations = try await networkService.createObservations([request])
			createdObservations.append(contentsOf: observations)
			await onProgress?(createdObservations.count, requests.count)

			if index < requests.count - 1, delayBetweenRequests > 0 {
				try? await Task.sleep(nanoseconds: UInt64(delayBetweenRequests * 1_000_000_000))
			}
		}

		return createdObservations
	}

	func scheduleTargets(
		_ targets: [WatchTarget],
		from start: Date,
		to end: Date,
		delayBetweenTargets: TimeInterval = 1,
		shouldCancel: (@MainActor () -> Bool)? = nil,
		onProgress: (@MainActor (AutoScheduleTargetResult) -> Void)? = nil
	) async -> AutoScheduleBatchResult {
		let enabledTargets = targets.filter { $0.enabled }
		let planner = AutoSchedulePlanner()

		do {
			let plan = try await planner.makePlan(
				targets: enabledTargets,
				start: start,
				end: end,
				priorityMode: .watchListOrder
			)

			let createdObservations = try await schedulePlan(
				plan,
				delayBetweenRequests: delayBetweenTargets,
				shouldCancel: shouldCancel,
				onProgress: nil
			)

			let createdByTargetID: [WatchTarget.ID?: [Observation]] = [:]

			let targetResults = enabledTargets.map { target in
				let createdCount = createdByTargetID[target.id]?.count ?? 0
				return AutoScheduleTargetResult(
					target: target,
					status: .success(createdCount: createdCount)
				)
			}

			for result in targetResults {
				await onProgress?(result)
			}

			return AutoScheduleBatchResult(
				results: targetResults,
				createdObservations: createdObservations
			)
		} catch {
			let targetResults = enabledTargets.map { target in
				AutoScheduleTargetResult(
					target: target,
					status: .failure(message: error.localizedDescription)
				)
			}

			for result in targetResults {
				await onProgress?(result)
			}

			return AutoScheduleBatchResult(
				results: targetResults,
				createdObservations: []
			)
		}
	}

	func schedule(
		target: WatchTarget,
		from start: Date,
		to end: Date,
		priorityMode: AutoSchedulePriorityMode = .watchListOrder
	) async throws -> [Observation] {
		let planner = AutoSchedulePlanner()
		let plan = try await planner.makePlan(
			targets: [target],
			start: start,
			end: end,
			priorityMode: priorityMode
		)
		return try await schedulePlan(plan)
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
