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
	@Published var isPlanning = false
	@Published var isScheduling = false
	@Published var scheduleProgress: (created: Int, total: Int) = (0, 0)
	@Published var executionResults: [AutoScheduleExecutionResult] = []
	@Published var message: String?

	private let planner: AutoSchedulePlanner
	private let scheduler: AutoScheduler
	private let settingsStore: AutoScheduleSettingsStore
	private var cancellables = Set<AnyCancellable>()

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
				}
			}
			.store(in: &cancellables)
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
		defer {
			isPlanning = false
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
					priorityMode: priorityMode
				)
			}

			createdObservations = []
			resetExecutionResults(for: plan)
			message = nil
		} catch {
			message = "Failed to calculate auto schedule plan: \(error.localizedDescription)"
		}
	}

	func scheduleSelectedPasses() async {
		guard let plan, !plan.selectedCandidates.isEmpty, !isScheduling else {
			return
		}

		isScheduling = true
		scheduleProgress = (0, plan.selectedCount)
		createdObservations = []
		resetExecutionResults(for: plan)
		defer {
			isScheduling = false
		}

		let summary = await scheduler.schedulePlanContinuingOnError(
			plan,
			delayBetweenRequests: 3,
			onResult: { result in
				self.updateExecutionResult(result)
			},
			onProgress: { created, total in
				self.scheduleProgress = (created, total)
			}
		)

		createdObservations = summary.createdObservations
		message = "Created \(summary.createdObservations.count) observation(s), failed \(summary.failureResults.count) request(s)."
	}
	
	func resortCurrentPlan(priorityMode: AutoSchedulePriorityMode) {
		guard !isPlanning && !isScheduling else {
			return
		}

		self.priorityMode = priorityMode
		if let plan {
			self.plan = plan.resorted(priorityMode: priorityMode)
			resetExecutionResults(for: self.plan)
		}
	}

	func executionResult(for candidate: AutoScheduleCandidate) -> AutoScheduleExecutionResult? {
		executionResults.first { result in
			result.candidate.id == candidate.id
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
