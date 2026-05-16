//
//  WatchTargetPredictionPreviewViewModel.swift
//  SatScheduler
//
//  Created by bi119aTe5hXk on 2026/05/16.
//
import Foundation
import Combine

@MainActor
final class WatchTargetPredictionPreviewViewModel: ObservableObject {
	@Published var isLoading = false
	@Published var errorMessage: String?
	@Published var stationTimelines: [StationPassTimeline] = []

	let startDate = Date()
	let endDate: Date = Calendar.current.date(byAdding: .day, value: 2, to: Date()) ?? Date().addingTimeInterval(2 * 24 * 60 * 60)

	private let dbService = SatNOGSDBService()
	private let passPredictor = PassPredictor()

	func loadPrediction(for target: WatchTarget) async {
		isLoading = true
		errorMessage = nil
		stationTimelines = []

		defer {
			isLoading = false
		}

		do {
			guard let tle = try await dbService.fetchLatestTLE(satelliteID: target.satelliteID) else {
				errorMessage = "TLE not found for satellite \(target.satelliteID)."
				return
			}

			let stationSnapshots = target.stationSnapshots ?? [:]

			var timelines: [StationPassTimeline] = []

			for stationID in target.stationIDs {
				guard let station = stationSnapshots[stationID] else {
					continue
				}

				let minimumElevation = target.minElevation ?? station.minHorizon ?? 0

				let passes = try passPredictor.predictPasses(
					tleName: tle.tle0,
					tleLine1: tle.tle1,
					tleLine2: tle.tle2,
					station: station,
					from: startDate,
					to: endDate,
					minimumElevation: minimumElevation
				)

				timelines.append(
					StationPassTimeline(
						stationID: station.id,
						stationName: station.name,
						passes: passes
					)
				)
			}

			let predictedTimelines = timelines.filter { !$0.passes.isEmpty }

			guard !predictedTimelines.isEmpty else {
				stationTimelines = []
				errorMessage = nil
				return
			}

			let requests = predictedTimelines.flatMap { stationTimeline in
				stationTimeline.passes.map { passWindow in
					ObservationScheduleRequest(
						groundStationID: stationTimeline.stationID,
						transmitterUUID: target.transmitterID,
						start: passWindow.start,
						end: passWindow.end
					)
				}
			}

			let stationIDs = Array(Set(requests.map(\.groundStationID))).sorted()
			let requestStart = requests.map(\.start).min() ?? startDate
			let requestEnd = requests.map(\.end).max() ?? endDate

			let existingObservations = try await SatNOGSNetworkService().fetchScheduledObservations(
				start: requestStart,
				end: requestEnd,
				groundStationIDs: stationIDs
			)

			let conflictResult = ObservationScheduleConflictResolver.filterConflicts(
				requests: requests,
				existingObservations: existingObservations,
				conflictBuffer: 30
			)

			let allowedPassKeys = Set(conflictResult.allowedRequests.map(Self.passKey))

			stationTimelines = predictedTimelines.compactMap { stationTimeline in
				let filteredPasses = stationTimeline.passes.filter { passWindow in
					allowedPassKeys.contains(Self.passKey(
						stationID: stationTimeline.stationID,
						start: passWindow.start,
						end: passWindow.end
					))
				}

				guard !filteredPasses.isEmpty else {
					return nil
				}

				return StationPassTimeline(
					stationID: stationTimeline.stationID,
					stationName: stationTimeline.stationName,
					passes: filteredPasses
				)
			}

			print("Prediction conflict filter: predicted \(requests.count), visible \(conflictResult.allowedRequests.count), hidden \(conflictResult.skippedRequests.count).")

			if stationTimelines.isEmpty {
				errorMessage = nil
			}
		} catch {
			errorMessage = error.localizedDescription
		}
	}
	private static func passKey(_ request: ObservationScheduleRequest) -> PassScheduleKey {
		passKey(
			stationID: request.groundStationID,
			start: request.start,
			end: request.end
		)
	}

	private static func passKey(
		stationID: Int,
		start: Date,
		end: Date
	) -> PassScheduleKey {
		PassScheduleKey(
			stationID: stationID,
			startTime: start.timeIntervalSince1970,
			endTime: end.timeIntervalSince1970
		)
	}
}

private struct PassScheduleKey: Hashable {
	let stationID: Int
	let startTime: TimeInterval
	let endTime: TimeInterval
}

struct StationPassTimeline: Identifiable, Hashable {
	let stationID: Int
	let stationName: String
	let passes: [PassWindow]

	var id: Int {
		stationID
	}

	var displayName: String {
		"\(stationName) (\(stationID))"
	}
}
