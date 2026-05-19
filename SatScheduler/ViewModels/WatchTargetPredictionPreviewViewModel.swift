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
	@Published var conflictSummary: PredictionConflictSummary?
	
	let startDate = Date()
	let endDate: Date = Calendar.current.date(byAdding: .day, value: 2, to: Date()) ?? Date().addingTimeInterval(2 * 24 * 60 * 60)

	private let dbService = SatNOGSDBService()
	private let passPredictor = PassPredictor()

	func loadPrediction(for target: WatchTarget) async {
		isLoading = true
		errorMessage = nil
		stationTimelines = []
		conflictSummary = nil

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

				let filteredPasses = passes.filter { passWindow in
					shouldIncludePassWindow(
						passWindow,
						target: target,
						station: station
					)
				}

				timelines.append(
					StationPassTimeline(
						stationID: station.id,
						stationName: station.name,
						passes: filteredPasses
					)
				)
			}

			let predictedTimelines = timelines.filter { !$0.passes.isEmpty }

			guard !predictedTimelines.isEmpty else {
				stationTimelines = []
				conflictSummary = nil
				errorMessage = nil
				return
			}
			
			
			print("Target satelliteID:", target.satelliteID)
			print("TransmitterID:", target.transmitterID)
			
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
			StationScheduleStore.shared.replaceSchedule(with: existingObservations)

			let conflictResult = ObservationScheduleConflictResolver.filterConflicts(
				requests: requests,
				existingObservations: existingObservations,
				conflictBuffer: 5 * 60
			)

			conflictSummary = PredictionConflictSummary(
				predictedCount: requests.count,
				visibleCount: conflictResult.allowedRequests.count,
				hiddenCount: conflictResult.skippedRequests.count
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

	private func shouldIncludePassWindow(
		_ passWindow: PassWindow,
		target: WatchTarget,
		station: WatchStationSnapshot
	) -> Bool {
		if let minPeakElevation = target.minPeakElevation,
		   passWindow.peakElevation < minPeakElevation {
			let formattedPeakElevation = String(format: "%.2f", passWindow.peakElevation)
			let formattedMinPeakElevation = String(format: "%.2f", minPeakElevation)
			print("Prediction skipped peak-elevation pass: target=\(target.satelliteID), station=\(station.id), peakElevation=\(formattedPeakElevation), minPeakElevation=\(formattedMinPeakElevation)")
			return false
		}

		if let maxPeakElevation = target.maxPeakElevation,
		   passWindow.peakElevation > maxPeakElevation {
			let formattedPeakElevation = String(format: "%.2f", passWindow.peakElevation)
			let formattedMaxPeakElevation = String(format: "%.2f", maxPeakElevation)
			print("Prediction skipped peak-elevation pass: target=\(target.satelliteID), station=\(station.id), peakElevation=\(formattedPeakElevation), maxPeakElevation=\(formattedMaxPeakElevation)")
			return false
		}

		if !passesAzimuthFilter(passWindow, target: target) {
			let formattedStartAzimuth = String(format: "%.2f", passWindow.azimuthStart)
			let formattedEndAzimuth = String(format: "%.2f", passWindow.azimuthEnd)
			let formattedMinAzimuth = target.minAzimuth.map { String(format: "%.2f", $0) } ?? "nil"
			let formattedMaxAzimuth = target.maxAzimuth.map { String(format: "%.2f", $0) } ?? "nil"
			print("Prediction skipped azimuth pass: target=\(target.satelliteID), station=\(station.id), azimuthStart=\(formattedStartAzimuth), azimuthEnd=\(formattedEndAzimuth), minAzimuth=\(formattedMinAzimuth), maxAzimuth=\(formattedMaxAzimuth)")
			return false
		}

		guard target.requiresStationDaylight else {
			return true
		}

		guard let latitude = station.latitude,
			  let longitude = station.longitude else {
			print("Prediction skipped daylight-only pass: station \(station.id) location is missing.")
			return false
		}

		let midpoint = passWindow.start.addingTimeInterval(
			passWindow.end.timeIntervalSince(passWindow.start) / 2
		)
		let solarElevation = SolarCalculator.solarElevation(
			date: midpoint,
			latitude: latitude,
			longitude: longitude
		)
		let isDaylight = SolarCalculator.isDaylight(
			date: midpoint,
			latitude: latitude,
			longitude: longitude
		)

		if !isDaylight {
			let formattedSolarElevation = String(format: "%.2f", solarElevation)
			print("Prediction skipped daylight-only pass: target=\(target.satelliteID), station=\(station.id), midpoint=\(midpoint), solarElevation=\(formattedSolarElevation)")
		}

		return isDaylight
	}

	private func passesAzimuthFilter(
		_ passWindow: PassWindow,
		target: WatchTarget
	) -> Bool {
		guard let minAzimuth = target.minAzimuth,
			  let maxAzimuth = target.maxAzimuth else {
			return true
		}

		return passWindow.azimuthSamples.contains { azimuth in
			isAzimuth(
				azimuth,
				insideRangeFrom: minAzimuth,
				to: maxAzimuth
			)
		}
	}

	private func isAzimuth(
		_ azimuth: Double,
		insideRangeFrom minAzimuth: Double,
		to maxAzimuth: Double
	) -> Bool {
		let normalizedAzimuth = normalizeAzimuth(azimuth)
		let normalizedMinAzimuth = normalizeAzimuth(minAzimuth)
		let normalizedMaxAzimuth = normalizeAzimuth(maxAzimuth)

		if normalizedMinAzimuth <= normalizedMaxAzimuth {
			return normalizedAzimuth >= normalizedMinAzimuth && normalizedAzimuth <= normalizedMaxAzimuth
		}

		return normalizedAzimuth >= normalizedMinAzimuth || normalizedAzimuth <= normalizedMaxAzimuth
	}

	private func normalizeAzimuth(_ azimuth: Double) -> Double {
		let normalized = azimuth.truncatingRemainder(dividingBy: 360)
		return normalized >= 0 ? normalized : normalized + 360
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

struct PredictionConflictSummary: Equatable {
	let predictedCount: Int
	let visibleCount: Int
	let hiddenCount: Int
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
