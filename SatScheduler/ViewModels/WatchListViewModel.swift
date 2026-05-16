//
//  WatchListViewModel.swift
//  SatScheduler
//
//  Created by bi119aTe5hXk on 2026/05/16.
//

import Foundation
import Combine
import SwiftUI

@MainActor
final class WatchListViewModel: ObservableObject {

	@Published var watchTargets: [WatchTarget] = []

	private let store: WatchTargetStore

	init(store: WatchTargetStore = .shared) {
		self.store = store

		NotificationCenter.default.addObserver(
			forName: NSUbiquitousKeyValueStore.didChangeExternallyNotification,
			object: NSUbiquitousKeyValueStore.default,
			queue: .main
		) { [weak self] _ in
			Task { @MainActor in
				self?.loadWatchTargets()
			}
		}
	}

	func loadWatchTargets() {
		watchTargets = store.loadWatchTargets()
	}

	func addTarget(_ target: WatchTarget) {
		watchTargets.append(target)
		saveWatchTargets()
	}

	func deleteTargets(at offsets: IndexSet) {
		watchTargets.remove(atOffsets: offsets)
		saveWatchTargets()
	}

	private func saveWatchTargets() {
		store.saveWatchTargets(watchTargets)
	}
	
	func autoScheduleAllTargets() async throws -> Int {

		let scheduler = AutoScheduler()
		let start = Date()
		let end = Calendar.current.date(byAdding: .day, value: 2, to: start) ?? start.addingTimeInterval(2 * 24 * 60 * 60)
		var createdCount = 0
		for target in watchTargets where target.enabled {
			let observations = try await scheduler.schedule(
				target: target,
				from: start,
				to: end
			)
			createdCount += observations.count
		}
		return createdCount

	}
}


