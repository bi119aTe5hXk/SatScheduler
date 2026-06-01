//
//  StationTimeLineViewModel.swift
//  SatScheduler
//
//  Created by bi119aTe5hXk on 2026/05/16.
//
import Foundation
import Combine

@MainActor
final class StationTimeLineViewModel: ObservableObject {
	@Published var stationSchedules: [StationScheduleTimeline] = []
	@Published var isLoading = false
	@Published var message: String?
	@Published private var lastUpdatedAt: Date?
	@Published var refreshingStationID: Int?

	@Published private(set) var startDate: Date
	@Published private(set) var endDate: Date

	private let store = StationScheduleStore.shared
	private let scheduleWindowDuration: TimeInterval = 3 * 24 * 60 * 60
	private var iCloudObserver: NSObjectProtocol?

	init() {
		let now = Date()
		startDate = now
		endDate = now.addingTimeInterval(scheduleWindowDuration)

		iCloudObserver = NotificationCenter.default.addObserver(
			forName: NSUbiquitousKeyValueStore.didChangeExternallyNotification,
			object: NSUbiquitousKeyValueStore.default,
			queue: .main
		) { [weak self] _ in
			guard let self else {
				return
			}

			Task { @MainActor in
				self.loadCachedSchedule()
			}
		}
	}

	deinit {
		if let iCloudObserver {
			NotificationCenter.default.removeObserver(iCloudObserver)
		}
	}

	var cacheStatusText: String {
		guard let lastUpdatedAt else {
			return "Showing cached data. No refresh has been performed yet."
		}

		return "Showing cached data. Last updated: \(formatDateTime(lastUpdatedAt))"
	}

	func loadCachedSchedule() {
		let cache = store.loadCachedSchedule()
		stationSchedules = timelinesFromWatchTargets(mergedWith: cache.stationSchedules)
		lastUpdatedAt = cache.updatedAt
	}

	func refresh() async {
		let stationIDs = stationSchedules.map(\.stationID)
		guard let firstStationID = stationIDs.first else {
			message = "No watched stations found."
			return
		}

		await refreshStation(firstStationID)
	}

	func refreshStation(_ stationID: Int) async {
		guard refreshingStationID == nil else {
			return
		}

		refreshingStationID = stationID
		defer {
			refreshingStationID = nil
		}
		do {
			let now = Date()
			startDate = now
			endDate = now.addingTimeInterval(scheduleWindowDuration)

			let cache = try await store.refreshSchedule(
				start: startDate,
				end: endDate,
				groundStationIDs: [stationID]
			)
			stationSchedules = timelinesFromWatchTargets(mergedWith: cache.stationSchedules)
			lastUpdatedAt = cache.updatedAt
			let stationDisplayName = stationSchedules.first { $0.stationID == stationID }?.stationName
			let stationName = stationDisplayName?.isEmpty == false ? stationDisplayName! : "Station"
			message = "\(stationName) (\(stationID)) schedule refreshed."
		} catch {
			message = "Refresh failed: \(error.localizedDescription)"
		}
	}

	private func timelinesFromWatchTargets(mergedWith cachedSchedules: [StationScheduleTimeline]) -> [StationScheduleTimeline] {
		let cachedByStationID = Dictionary(uniqueKeysWithValues: cachedSchedules.map { ($0.stationID, $0) })

		let watchedStations = WatchTargetStore.shared.loadWatchTargets()
			.flatMap { target in
				target.stationIDs.map { stationID in
					(stationID, cachedByStationID[stationID]?.stationName ?? "Station \(stationID)")
				}
			}
			.removingDuplicates { $0.0 }
			.sorted { $0.0 < $1.0 }

		return watchedStations.map { stationID, stationName in
			if let cached = cachedByStationID[stationID] {
				return StationScheduleTimeline(
					stationID: stationID,
					stationName: cached.stationName.isEmpty ? stationName : cached.stationName,
					observations: cached.observations
				)
			}

			return StationScheduleTimeline(
				stationID: stationID,
				stationName: stationName,
				observations: []
			)
		}
	}

	private func formatDateTime(_ date: Date) -> String {
		let formatter = DateFormatter()
		formatter.locale = Locale(identifier: "en_US_POSIX")
		formatter.timeZone = TimeZone(secondsFromGMT: 0)
		formatter.dateFormat = "yyyy-MM-dd HH:mm:ss 'UTC'"
		return formatter.string(from: date)
	}
}

struct StationScheduleCache: Codable, Hashable {
	let updatedAt: Date?
	let stationSchedules: [StationScheduleTimeline]
}

struct StationScheduleTimeline: Identifiable, Codable, Hashable {
	let stationID: Int
	let stationName: String
	let observations: [StationScheduleObservation]

	var id: Int {
		stationID
	}

	var displayName: String {
		stationName.isEmpty ? "Station \(stationID)" : "\(stationName) (\(stationID))"
	}
}

struct StationScheduleObservation: Identifiable, Codable, Hashable {
	let id: Int
	let stationID: Int
	let stationName: String
	let satelliteName: String
	let tle0: String?
	let transmitterDescription: String
	let start: Date
	let end: Date

	var durationText: String {
		let minutes = Int(end.timeIntervalSince(start) / 60)
		return "\(minutes)m"
	}
}

private extension Array {
	func removingDuplicates<ID: Hashable>(by id: (Element) -> ID) -> [Element] {
		var seen = Set<ID>()
		return filter { seen.insert(id($0)).inserted }
	}
}
