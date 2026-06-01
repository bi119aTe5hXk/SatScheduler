//
//  AutoScheduleStationTimelineRow.swift
//  SatScheduler
//
//  Created by bi119aTe5hXk on 2026/05/19.
//

import SwiftUI

struct AutoScheduleStationTimelineRow: View {
	let stationID: Int
	let plan: AutoSchedulePlan
	let timelineObservations: [Observation]
	let createdObservations: [Observation]
	let executionResults: [AutoScheduleExecutionResult]

	private var stationName: String {
		plan.selectedCandidates.first { $0.request.groundStationID == stationID }?.stationName
			?? executionResults.first { $0.candidate.request.groundStationID == stationID }?.candidate.stationName
			?? "Station \(stationID)"
	}

	private var existingObservations: [Observation] {
		timelineObservations.filter { observation in
			observation.ground_station == stationID && !createdObservationIDs.contains(observation.id)
		}
	}

	private var createdObservationIDs: Set<Int> {
		Set(createdObservations.map(\.id))
	}

	private var successfulCreatedObservations: [Observation] {
		createdObservations.filter { observation in
			observation.ground_station == stationID
		}
	}

	private var plannedCandidates: [AutoScheduleCandidate] {
		plan.selectedCandidates.filter { candidate in
			guard candidate.request.groundStationID == stationID else {
				return false
			}

			guard let executionResult = executionResult(for: candidate) else {
				return true
			}

			switch executionResult.status {
			case .pending, .running:
				return true
			case .success, .failure:
				return false
			}
		}
	}

	private var successfulCandidates: [AutoScheduleCandidate] {
		guard successfulCreatedObservations.isEmpty else {
			return []
		}

		return executionResults.compactMap { result in
			guard result.candidate.request.groundStationID == stationID,
				  case .success = result.status else {
				return nil
			}

			return result.candidate
		}
	}

	private var failedCandidates: [AutoScheduleCandidate] {
		executionResults.compactMap { result in
			guard result.candidate.request.groundStationID == stationID,
				  case .failure = result.status else {
				return nil
			}

			return result.candidate
		}
	}

	private var hasExecutionResults: Bool {
		executionResults.contains { result in
			result.candidate.request.groundStationID == stationID
		}
	}

	var body: some View {
		VStack(alignment: .leading, spacing: 6) {
			Text(stationName)
				.font(.caption)
				.foregroundStyle(.secondary)

			if hasExecutionResults {
				HStack(spacing: 10) {
					Label("Pending", systemImage: "rectangle.fill")
						.foregroundStyle(.yellow)
					Label("Success", systemImage: "rectangle.fill")
						.foregroundStyle(.green)
					Label("Failed", systemImage: "rectangle.fill")
						.foregroundStyle(.red)
				}
				.font(.caption2)
			}

			AutoScheduleTimelineBar(
				start: plan.start,
				end: plan.end,
				existingObservations: existingObservations,
				plannedCandidates: plannedCandidates,
				successfulCreatedObservations: successfulCreatedObservations,
				successfulCandidates: successfulCandidates,
				failedCandidates: failedCandidates
			)
			.frame(height: 28)
		}
	}
	

	private func executionResult(for candidate: AutoScheduleCandidate) -> AutoScheduleExecutionResult? {
		executionResults.first { result in
			result.candidate.id == candidate.id
		}
	}
}





