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

	func schedulePlanContinuingOnError(
		_ plan: AutoSchedulePlan,
		delayBetweenRequests: TimeInterval = 0,
		shouldCancel: (@MainActor () -> Bool)? = nil,
		onResult: (@MainActor (AutoScheduleExecutionResult) -> Void)? = nil,
		onProgress: (@MainActor (Int, Int) -> Void)? = nil
	) async -> AutoScheduleExecutionSummary {
		var results: [AutoScheduleExecutionResult] = []
		var createdObservations: [Observation] = []
		let candidates = plan.selectedCandidates

		for (index, candidate) in candidates.enumerated() {
			if await shouldCancel?() == true {
				let cancelledResult = AutoScheduleExecutionResult(
					candidate: candidate,
					status: .failure(message: "Cancelled")
				)
				results.append(cancelledResult)
				await onResult?(cancelledResult)
				await onProgress?(createdObservations.count, candidates.count)
				break
			}

			let runningResult = AutoScheduleExecutionResult(
				candidate: candidate,
				status: .running
			)
			await onResult?(runningResult)

			do {
				let observations = try await networkService.createObservations([candidate.request])
				createdObservations.append(contentsOf: observations)

				let successResult = AutoScheduleExecutionResult(
					candidate: candidate,
					status: .success(createdCount: observations.count)
				)
				results.append(successResult)
				await onResult?(successResult)
			} catch {
				let failureResult = AutoScheduleExecutionResult(
					candidate: candidate,
					status: .failure(message: error.localizedDescription)
				)
				results.append(failureResult)
				await onResult?(failureResult)
			}

			await onProgress?(createdObservations.count, candidates.count)

			if index < candidates.count - 1, delayBetweenRequests > 0 {
				try? await Task.sleep(nanoseconds: UInt64(delayBetweenRequests * 1_000_000_000))
			}
		}

		return AutoScheduleExecutionSummary(
			results: results,
			createdObservations: createdObservations
		)
	}

	func schedulePlanBatch(
		_ plan: AutoSchedulePlan,
		shouldCancel: (@MainActor () -> Bool)? = nil,
		onResult: (@MainActor (AutoScheduleExecutionResult) -> Void)? = nil,
		onProgress: (@MainActor (Int, Int) -> Void)? = nil
	) async -> AutoScheduleExecutionSummary {
		let candidates = plan.selectedCandidates
		guard !candidates.isEmpty else {
			return AutoScheduleExecutionSummary(results: [], createdObservations: [])
		}

		if await shouldCancel?() == true {
			let cancelledResults = candidates.map { candidate in
				AutoScheduleExecutionResult(
					candidate: candidate,
					status: .failure(message: "Cancelled")
				)
			}

			for result in cancelledResults {
				await onResult?(result)
			}
			await onProgress?(0, candidates.count)

			return AutoScheduleExecutionSummary(
				results: cancelledResults,
				createdObservations: []
			)
		}

		for candidate in candidates {
			await onResult?(
				AutoScheduleExecutionResult(
					candidate: candidate,
					status: .running
				)
			)
		}

		let shouldCancelBeforeRequest = await shouldCancel?() == true
		if Task.isCancelled || shouldCancelBeforeRequest {
			let cancelledResults = candidates.map { candidate in
				AutoScheduleExecutionResult(
					candidate: candidate,
					status: .failure(message: "Cancelled")
				)
			}

			for result in cancelledResults {
				await onResult?(result)
			}
			await onProgress?(0, candidates.count)

			return AutoScheduleExecutionSummary(
				results: cancelledResults,
				createdObservations: []
			)
		}

		do {
			let createdObservations = try await networkService.createObservations(plan.requests)
			let matchedObservationIDsByCandidateID = matchCreatedObservations(
				createdObservations,
				to: candidates
			)

			var results: [AutoScheduleExecutionResult] = []

			for candidate in candidates {
				let matchedObservationIDs = matchedObservationIDsByCandidateID[candidate.id] ?? []

				let result: AutoScheduleExecutionResult
				if matchedObservationIDs.isEmpty {
					result = AutoScheduleExecutionResult(
						candidate: candidate,
						status: .failure(message: "Observation was not returned by SatNOGS Network.")
					)
				} else {
					result = AutoScheduleExecutionResult(
						candidate: candidate,
						status: .success(createdCount: matchedObservationIDs.count)
					)
				}

				results.append(result)
				await onResult?(result)
			}

			await onProgress?(createdObservations.count, candidates.count)

			return AutoScheduleExecutionSummary(
				results: results,
				createdObservations: createdObservations
			)
		} catch {
			let shouldCancelAfterError = await shouldCancel?() == true
			if Task.isCancelled || error is CancellationError || shouldCancelAfterError {
				let cancelledResults = candidates.map { candidate in
					AutoScheduleExecutionResult(
						candidate: candidate,
						status: .failure(message: "Cancelled")
					)
				}

				for result in cancelledResults {
					await onResult?(result)
				}
				await onProgress?(0, candidates.count)

				return AutoScheduleExecutionSummary(
					results: cancelledResults,
					createdObservations: []
				)
			}

			let failureResults = candidates.map { candidate in
				AutoScheduleExecutionResult(
					candidate: candidate,
					status: .failure(message: error.localizedDescription)
				)
			}

			for result in failureResults {
				await onResult?(result)
			}
			await onProgress?(0, candidates.count)

			return AutoScheduleExecutionSummary(
				results: failureResults,
				createdObservations: []
			)
		}
	}

	private func matchCreatedObservations(
		_ observations: [Observation],
		to candidates: [AutoScheduleCandidate]
	) -> [AutoScheduleCandidate.ID: [Int]] {
		var unmatchedObservations = observations
		var matchedObservationIDsByCandidateID: [AutoScheduleCandidate.ID: [Int]] = [:]

		for candidate in candidates {
			guard let matchIndex = unmatchedObservations.firstIndex(where: { observation in
				isCreatedObservation(observation, matching: candidate)
			}) else {
				continue
			}

			let observation = unmatchedObservations.remove(at: matchIndex)
			matchedObservationIDsByCandidateID[candidate.id, default: []].append(observation.id)
		}

		return matchedObservationIDsByCandidateID
	}

	private func isCreatedObservation(
		_ observation: Observation,
		matching candidate: AutoScheduleCandidate
	) -> Bool {
		guard observation.ground_station == candidate.request.groundStationID,
			  let observationStart = observation.startDate,
			  let observationEnd = observation.endDate else {
			return false
		}

		let startDelta = abs(observationStart.timeIntervalSince(candidate.request.start))
		let endDelta = abs(observationEnd.timeIntervalSince(candidate.request.end))
		return startDelta <= 60 && endDelta <= 60
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

			let executionSummary = await schedulePlanContinuingOnError(
				plan,
				delayBetweenRequests: delayBetweenTargets,
				shouldCancel: shouldCancel,
				onResult: nil,
				onProgress: nil
			)
			let createdObservations = executionSummary.createdObservations

			let resultsByTargetID = Dictionary(grouping: executionSummary.results) { result in
				result.candidate.target.id
			}

			let targetResults = enabledTargets.map { target in
				let targetExecutionResults = resultsByTargetID[target.id] ?? []
				let createdCount = targetExecutionResults.reduce(0) { partialResult, executionResult in
					if case .success(let createdCount) = executionResult.status {
						return partialResult + createdCount
					}

					return partialResult
				}

				if let failedResult = targetExecutionResults.first(where: { result in
					if case .failure = result.status {
						return true
					}

					return false
				}),
				case .failure(let message) = failedResult.status,
				createdCount == 0 {
					return AutoScheduleTargetResult(
						target: target,
						status: .failure(message: message)
					)
				}

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
		let summary = await schedulePlanContinuingOnError(plan)
		if summary.createdObservations.isEmpty, let firstFailure = summary.failureResults.first,
		   case .failure(let message) = firstFailure.status {
			throw AutoSchedulerError.requestFailed(message)
		}

		return summary.createdObservations
	}
}

enum AutoSchedulerError: LocalizedError {
	case tleNotFound(String)
	case stationSnapshotNotFound
	case requestFailed(String)

	var errorDescription: String? {
		switch self {
		case .tleNotFound(let satelliteID):
			return "TLE not found for satellite \(satelliteID)."
		case .stationSnapshotNotFound:
			return "Station snapshot not found. Please refresh the watch target stations."
		case .requestFailed(let message):
			return message
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
