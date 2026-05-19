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

				if self.plan == nil && !self.isPlanning && !self.isScheduling {
					self.priorityMode = priorityMode
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
			plan = try await planner.makePlan(
				targets: targets,
				start: start,
				end: end,
				priorityMode: priorityMode
			)
			createdObservations = []
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
		defer {
			isScheduling = false
		}

		do {
			let observations = try await scheduler.schedulePlan(
				plan,
				delayBetweenRequests: 1,
				onProgress: { created, total in
					self.scheduleProgress = (created, total)
				}
			)
			createdObservations = observations
			message = "Created \(observations.count) observation(s)."
		} catch {
			message = "Failed to schedule observations: \(error.localizedDescription)"
		}
	}
	
	func resortCurrentPlan(priorityMode: AutoSchedulePriorityMode) {
		self.priorityMode = priorityMode
		if let plan {
			self.plan = plan.resorted(priorityMode: priorityMode)
		}
	}

	func clearMessage() {
		message = nil
	}
}
