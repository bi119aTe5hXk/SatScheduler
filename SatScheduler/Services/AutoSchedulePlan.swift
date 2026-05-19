//
//  AutoSchedulePlan.swift
//  SatScheduler
//
//  Created by bi119aTe5hXk on 2026/05/19.
//

import Foundation

enum AutoSchedulePriorityMode: String, CaseIterable, Codable, Identifiable {
	case watchListOrder
	case watchListOrderThenPeakElevation
	case peakElevationFirst

	var id: String {
		rawValue
	}

	var title: String {
		switch self {
		case .watchListOrder:
			return "Watch List order"
		case .watchListOrderThenPeakElevation:
			return "Watch List order + best elevation"
		case .peakElevationFirst:
			return "Best elevation first"
		}
	}

	var description: String {
		switch self {
		case .watchListOrder:
			return "Use the manual Watch List order as the scheduling priority."
		case .watchListOrderThenPeakElevation:
			return "Keep Watch List priority, but prefer higher peak elevation when choosing passes for the same target."
		case .peakElevationFirst:
			return "Prefer higher peak elevation across all targets, regardless of Watch List order."
		}
	}
}

struct AutoSchedulePlan: Identifiable {
	let id = UUID()
	let createdAt: Date
	let start: Date
	let end: Date
	let priorityMode: AutoSchedulePriorityMode
	let candidates: [AutoScheduleCandidate]
	let selectedCandidates: [AutoScheduleCandidate]
	let skippedCandidates: [AutoScheduleSkippedCandidate]
	let existingObservations: [Observation]

	var requests: [ObservationScheduleRequest] {
		selectedCandidates.map(\.request)
	}

	var selectedCount: Int {
		selectedCandidates.count
	}

	var candidateCount: Int {
		candidates.count
	}

	var skippedCount: Int {
		skippedCandidates.count
	}

	func resorted(priorityMode: AutoSchedulePriorityMode) -> AutoSchedulePlan {
		let sortedCandidates = AutoSchedulePlanner.sortCandidates(candidates, priorityMode: priorityMode)
		let selection = AutoSchedulePlanner.selectNonConflictingCandidates(
			sortedCandidates,
			existingObservations: existingObservations
		)

		return AutoSchedulePlan(
			createdAt: createdAt,
			start: start,
			end: end,
			priorityMode: priorityMode,
			candidates: candidates,
			selectedCandidates: selection.selected,
			skippedCandidates: selection.skipped,
			existingObservations: existingObservations
		)
	}
}

struct AutoScheduleCandidate: Identifiable, Hashable {
	let id = UUID()
	let target: WatchTarget
	let targetIndex: Int
	let station: WatchStationSnapshot
	let passWindow: PassWindow
	let request: ObservationScheduleRequest

	var satelliteName: String {
		target.satelliteName ?? target.name
	}

	var stationName: String {
		station.name ?? "Station \(station.id)"
	}

	var peakElevation: Double {
		passWindow.peakElevation
	}

	var duration: TimeInterval {
		passWindow.end.timeIntervalSince(passWindow.start)
	}
}

struct AutoScheduleSkippedCandidate: Identifiable, Hashable {
	let id = UUID()
	let candidate: AutoScheduleCandidate
	let reason: AutoScheduleSkipReason
	let conflictingCandidate: AutoScheduleCandidate?
}

enum AutoScheduleSkipReason: Hashable {
	case conflictWithSelected
	case conflictWithExistingObservation

	var title: String {
		switch self {
		case .conflictWithSelected:
			return "Conflicts with selected pass"
		case .conflictWithExistingObservation:
			return "Conflicts with existing observation"
		}
	}
}

struct AutoScheduleExecutionResult: Identifiable {
	let id = UUID()
	let candidate: AutoScheduleCandidate
	let status: AutoScheduleExecutionStatus
}

enum AutoScheduleExecutionStatus: Equatable {

	case pending
	case running
	case success(createdCount: Int)
	case failure(message: String)
	var title: String {
		switch self {
		case .pending:
			return "Pending"
		case .running:
			return "Running"
		case .success(let createdCount):
			return "Created \(createdCount)"
		case .failure(let message):
			return "Failed: \(message)"
		}
	}
}
struct AutoScheduleExecutionSummary {
	let results: [AutoScheduleExecutionResult]
	let createdObservations: [Observation]
	var successResults: [AutoScheduleExecutionResult] {
		results.filter { result in
			if case .success = result.status {
				return true
			}
			return false
		}
	}
	var failureResults: [AutoScheduleExecutionResult] {
		results.filter { result in
			if case .failure = result.status {
				return true
			}
			return false
		}
	}
}
