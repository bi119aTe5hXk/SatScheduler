//
//  AutoSchedulePreviewViewModel.swift
//  SatScheduler
//
//  Created by bi119aTe5hXk on 2026/05/19.
//

import Foundation
import Combine

@MainActor
final class AutoSchedulePreviewViewModel: ObservableObject {
	@Published var priorityMode: AutoSchedulePriorityMode = .watchListOrder
	@Published var plan: AutoSchedulePlan?
	@Published var createdObservations: [Observation] = []
	@Published var timelineObservations: [Observation] = []
	@Published var isPlanning = false
	@Published var planningStatusText = ""
	@Published var isScheduling = false
	@Published private(set) var isRetryingFailedPasses = false
	@Published var scheduleProgress: (created: Int, total: Int) = (0, 0)
	@Published var executionResults: [AutoScheduleExecutionResult] = []
	@Published var message: String?

	private let planner: AutoSchedulePlanner
	private let scheduler: AutoScheduler
	private let settingsStore: AutoScheduleSettingsStore
	private var cancellables = Set<AnyCancellable>()
	private var isSchedulingCancellationRequested = false

	init(
		planner: AutoSchedulePlanner = AutoSchedulePlanner(),
		scheduler: AutoScheduler = AutoScheduler(),
		settingsStore: AutoScheduleSettingsStore = .shared
	) {
		self.planner = planner
		self.scheduler = scheduler
		self.settingsStore = settingsStore
		self.priorityMode = settingsStore.settings.priorityMode

		settingsStore.$settings
			.map(\.priorityMode)
			.removeDuplicates()
			.sink { [weak self] priorityMode in
				guard let self else {
					return
				}

				guard !self.isPlanning && !self.isScheduling else {
					return
				}

				self.priorityMode = priorityMode
				if let plan = self.plan {
					self.plan = plan.resorted(priorityMode: priorityMode)
					self.resetExecutionResults(for: self.plan)
					self.resetTimelineObservations(for: self.plan)
				}
			}
			.store(in: &cancellables)
	}

	var hasRetryableFailedPasses: Bool {
		guard let plan else {
			return false
		}

		return !failedCandidates(in: plan).isEmpty
	}

	var hasCompletedScheduleSuccessfully: Bool {
		guard let plan, !plan.selectedCandidates.isEmpty else {
			return false
		}

		return plan.selectedCandidates.allSatisfy { candidate in
			guard let result = executionResult(for: candidate),
				  case .success = result.status else {
				return false
			}

			return true
		}
	}

	var canStartScheduling: Bool {
		guard let plan, !plan.selectedCandidates.isEmpty else {
			return false
		}

		if hasRetryableFailedPasses {
			return true
		}

		if hasCompletedScheduleSuccessfully {
			return false
		}

		return plan.selectedCandidates.contains { candidate in
			guard let result = executionResult(for: candidate) else {
				return true
			}

			switch result.status {
			case .pending, .running:
				return true
			case .success, .failure:
				return false
			}
		}
	}

	var scheduleButtonTitle: String {
		if hasRetryableFailedPasses {
			return "Retry Failed Passes"
		}

		if hasCompletedScheduleSuccessfully {
			return "Submitted"
		}

		return "Schedule Selected Passes"
	}

	var scheduleButtonSystemImage: String {
		if hasRetryableFailedPasses {
			return "arrow.clockwise"
		}

		if hasCompletedScheduleSuccessfully {
			return "checkmark.circle"
		}

		return "paperplane"
	}

	func makePlan(
		targets: [WatchTarget],
		start: Date,
		end: Date
	) async {
		guard !isPlanning else {
			return
		}

		isPlanning = true
		planningStatusText = "Preparing auto schedule plan..."
		defer {
			isPlanning = false
			planningStatusText = ""
		}

		do {
			if let currentPlan = plan,
			   currentPlan.start == start,
			   currentPlan.end == end {
				plan = currentPlan.resorted(priorityMode: priorityMode)
			} else {
				plan = try await planner.makePlan(
					targets: targets,
					start: start,
					end: end,
					priorityMode: priorityMode,
					onProgress: { status in
						await MainActor.run {
							self.planningStatusText = status.message
						}
					}
				)
			}

			createdObservations = []
			resetExecutionResults(for: plan)
			resetTimelineObservations(for: plan)
			message = nil
		} catch {
			timelineObservations = []
			message = "Failed to calculate auto schedule plan: \(error.localizedDescription)"
		}
	}

	func cancelScheduling() {
		isSchedulingCancellationRequested = true
	}

	func scheduleSelectedPasses() async {
		guard let plan, !plan.selectedCandidates.isEmpty, !isScheduling, canStartScheduling else {
			return
		}

		let shouldRetryFailedPasses = hasRetryableFailedPasses
		let schedulingPlan = shouldRetryFailedPasses ? retryPlan(from: plan) : plan
		guard !schedulingPlan.selectedCandidates.isEmpty else {
			return
		}

		isScheduling = true
		isRetryingFailedPasses = shouldRetryFailedPasses
		isSchedulingCancellationRequested = false
		scheduleProgress = (0, schedulingPlan.selectedCount)

		if shouldRetryFailedPasses {
			markCandidatesPending(schedulingPlan.selectedCandidates)
		} else {
			createdObservations = []
			resetExecutionResults(for: plan)
			resetTimelineObservations(for: plan)
		}

		defer {
			isScheduling = false
			isRetryingFailedPasses = false
			isSchedulingCancellationRequested = false
		}

		let summary = await scheduler.schedulePlanBatch(
			schedulingPlan,
			shouldCancel: {
				self.isSchedulingCancellationRequested
			},
			onResult: { result in
				self.updateExecutionResult(result)
			},
			onProgress: { created, total in
				self.scheduleProgress = (created, total)
			}
		)

		guard !isSchedulingCancellationRequested else {
			message = nil
			return
		}

		let mergedCreatedObservations = mergedObservations(
			createdObservations + summary.createdObservations
		)
		createdObservations = mergedCreatedObservations

		if !summary.createdObservations.isEmpty {
			StationScheduleStore.shared.mergeCreatedObservations(summary.createdObservations)
		}
		updateTimelineObservations(
			existingObservations: plan.existingObservations,
			createdObservations: mergedCreatedObservations
		)

		if shouldRetryFailedPasses {
			message = "Retried failed passes. Created \(summary.createdObservations.count) observation(s), failed \(summary.failureResults.count) request(s)."
		} else {
			message = "Created \(summary.createdObservations.count) observation(s), failed \(summary.failureResults.count) request(s)."
		}
	}
	
	func resortCurrentPlan(priorityMode: AutoSchedulePriorityMode) {
		guard !isPlanning && !isScheduling else {
			return
		}

		self.priorityMode = priorityMode
		if let plan {
			self.plan = plan.resorted(priorityMode: priorityMode)
			resetExecutionResults(for: self.plan)
			resetTimelineObservations(for: self.plan)
		}
	}

	func executionResult(for candidate: AutoScheduleCandidate) -> AutoScheduleExecutionResult? {
		executionResults.first { result in
			result.candidate.id == candidate.id
		}
	}

	private func failedCandidates(in plan: AutoSchedulePlan) -> [AutoScheduleCandidate] {
		plan.selectedCandidates.filter { candidate in
			guard let result = executionResult(for: candidate),
				  case .failure = result.status else {
				return false
			}

			return true
		}
	}

	private func retryPlan(from plan: AutoSchedulePlan) -> AutoSchedulePlan {
		AutoSchedulePlan(
			createdAt: plan.createdAt,
			start: plan.start,
			end: plan.end,
			priorityMode: plan.priorityMode,
			candidates: plan.candidates,
			selectedCandidates: failedCandidates(in: plan),
			skippedCandidates: plan.skippedCandidates,
			existingObservations: plan.existingObservations
		)
	}

	private func markCandidatesPending(_ candidates: [AutoScheduleCandidate]) {
		for candidate in candidates {
			updateExecutionResult(
				AutoScheduleExecutionResult(
					candidate: candidate,
					status: .pending
				)
			)
		}
	}

	private func resetTimelineObservations(for plan: AutoSchedulePlan?) {
		guard let plan else {
			timelineObservations = []
			return
		}

		timelineObservations = sortedObservations(plan.existingObservations)
	}

	private func updateTimelineObservations(
		existingObservations: [Observation],
		createdObservations: [Observation]
	) {
		var observationsByID: [Int: Observation] = [:]

		for observation in existingObservations + createdObservations {
			observationsByID[observation.id] = observation
		}

		timelineObservations = sortedObservations(Array(observationsByID.values))
	}

	private func mergedObservations(_ observations: [Observation]) -> [Observation] {
		var observationsByID: [Int: Observation] = [:]

		for observation in observations {
			observationsByID[observation.id] = observation
		}

		return sortedObservations(Array(observationsByID.values))
	}

	private func sortedObservations(_ observations: [Observation]) -> [Observation] {
		observations.sorted { lhs, rhs in
			let lhsStart = lhs.startDate ?? .distantPast
			let rhsStart = rhs.startDate ?? .distantPast
			return lhsStart < rhsStart
		}
	}

	private func resetExecutionResults(for plan: AutoSchedulePlan?) {
		guard let plan else {
			executionResults = []
			return
		}

		executionResults = plan.selectedCandidates.map { candidate in
			AutoScheduleExecutionResult(
				candidate: candidate,
				status: .pending
			)
		}
	}

	private func updateExecutionResult(_ result: AutoScheduleExecutionResult) {
		if let index = executionResults.firstIndex(where: { existingResult in
			existingResult.candidate.id == result.candidate.id
		}) {
			executionResults[index] = result
		} else {
			executionResults.append(result)
		}
	}

	func clearMessage() {
		message = nil
	}
	
	func removeSelectedCandidate(_ candidate: AutoScheduleCandidate) {
		guard !isScheduling, let currentPlan = plan else {
			return
		}

		let remainingCandidates = currentPlan.candidates.filter { $0.id != candidate.id }
		let remainingSelectedCandidates = currentPlan.selectedCandidates.filter { $0.id != candidate.id }
		let remainingSkippedCandidates = currentPlan.skippedCandidates.filter { skippedCandidate in
			skippedCandidate.candidate.id != candidate.id &&
			skippedCandidate.conflictingCandidate?.id != candidate.id
		}

		plan = AutoSchedulePlan(
			createdAt: currentPlan.createdAt,
			start: currentPlan.start,
			end: currentPlan.end,
			priorityMode: currentPlan.priorityMode,
			candidates: remainingCandidates,
			selectedCandidates: remainingSelectedCandidates,
			skippedCandidates: remainingSkippedCandidates,
			existingObservations: currentPlan.existingObservations
		)

		executionResults.removeAll { result in
			result.candidate.id == candidate.id
		}
		scheduleProgress = (createdObservations.count, remainingSelectedCandidates.count)
	}
	
	func moveSelectedCandidates(fromOffsets source: IndexSet, toOffset destination: Int) {
		guard !isScheduling, let currentPlan = plan else {
			return
		}

		var reorderedSelectedCandidates = currentPlan.selectedCandidates
		let movingCandidates = source.sorted().map { reorderedSelectedCandidates[$0] }

		for index in source.sorted(by: >) {
			reorderedSelectedCandidates.remove(at: index)
		}

		let adjustedDestination = destination - source.filter { $0 < destination }.count
		let insertionIndex = max(0, min(adjustedDestination, reorderedSelectedCandidates.count))
		reorderedSelectedCandidates.insert(contentsOf: movingCandidates, at: insertionIndex)

		plan = AutoSchedulePlan(
			createdAt: currentPlan.createdAt,
			start: currentPlan.start,
			end: currentPlan.end,
			priorityMode: currentPlan.priorityMode,
			candidates: currentPlan.candidates,
			selectedCandidates: reorderedSelectedCandidates,
			skippedCandidates: currentPlan.skippedCandidates,
			existingObservations: currentPlan.existingObservations
		)

		executionResults = reorderedSelectedCandidates.map { candidate in
			executionResults.first { result in
				result.candidate.id == candidate.id
			} ?? AutoScheduleExecutionResult(
				candidate: candidate,
				status: .pending
			)
		}
	}
}
