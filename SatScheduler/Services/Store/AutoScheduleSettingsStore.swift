//
//  AutoScheduleSettingsStore.swift
//  SatScheduler
//
//  Created by bi119aTe5hXk on 2026/05/19.
//

import Foundation
import Combine

struct AutoScheduleSettings: Codable, Equatable {
	var showPreviewBeforeScheduling: Bool = true
	var priorityMode: AutoSchedulePriorityMode = .watchListOrder
	var scheduleBatchSize: Int = 10

	var normalized: AutoScheduleSettings {
		var normalizedSettings = self
		normalizedSettings.scheduleBatchSize = min(max(scheduleBatchSize, 1), 50)
		return normalizedSettings
	}
}

@MainActor
final class AutoScheduleSettingsStore: ObservableObject {
	static let shared = AutoScheduleSettingsStore()

	@Published private(set) var settings = AutoScheduleSettings()

	private let store = NSUbiquitousKeyValueStore.default
	private let settingsKey = "SatScheduler.autoScheduleSettings"

	private init() {
		loadSettings()

		NotificationCenter.default.addObserver(
			forName: NSUbiquitousKeyValueStore.didChangeExternallyNotification,
			object: store,
			queue: .main
		) { [weak self] _ in
			Task { @MainActor in
				self?.loadSettings()
			}
		}

		store.synchronize()
	}

	func update(showPreviewBeforeScheduling: Bool) {
		var newSettings = settings
		newSettings.showPreviewBeforeScheduling = showPreviewBeforeScheduling
		save(newSettings)
	}

	func update(priorityMode: AutoSchedulePriorityMode) {
		var newSettings = settings
		newSettings.priorityMode = priorityMode
		save(newSettings)
	}

	func update(scheduleBatchSize: Int) {
		var newSettings = settings
		newSettings.scheduleBatchSize = min(max(scheduleBatchSize, 1), 50)
		save(newSettings)
	}

	private func loadSettings() {
		guard let data = store.data(forKey: settingsKey),
			  let decoded = try? JSONDecoder().decode(AutoScheduleSettings.self, from: data) else {
			settings = AutoScheduleSettings()
			return
		}
		settings = decoded.normalized
	}

	private func save(_ newSettings: AutoScheduleSettings) {
		let normalizedSettings = newSettings.normalized
		settings = normalizedSettings

		if let data = try? JSONEncoder().encode(normalizedSettings) {
			store.set(data, forKey: settingsKey)
			store.synchronize()
		}
	}
}
