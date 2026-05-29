//
//  AutoSchedulePlanner.swift
//  SatScheduler
//
//  Created by bi119aTe5hXk on 2026/05/19.
//

import Foundation

final class AutoSchedulePlanner {
	private let dbService = SatNOGSDBService()
	private let networkService = SatNOGSNetworkService()
	private let passPredictor = PassPredictor()

	func makePlan(
		targets: [WatchTarget],
		start: Date,
		end: Date,
		priorityMode: AutoSchedulePriorityMode,
		onProgress: ((AutoSchedulePlanningStatus) async -> Void)? = nil
	) async throws -> AutoSchedulePlan {
		var candidates: [AutoScheduleCandidate] = []
		await onProgress?(AutoSchedulePlanningStatus(message: "Preparing watch targets..."))
		let enabledTargets = targets.filter { $0.enabled }

		await onProgress?(AutoSchedulePlanningStatus(message: "Fetching TLE data from local cache or SatNOGS DB..."))
		let tleBySatelliteID = try await fetchTLEs(for: enabledTargets)

		await onProgress?(AutoSchedulePlanningStatus(message: "Predicting satellite pass windows from TLE data..."))
		for (targetIndex, target) in enabledTargets.enumerated() {
			await onProgress?(AutoSchedulePlanningStatus(message: "Predicting pass windows for \(target.name)..."))

			guard let tle = tleBySatelliteID[target.satelliteID] else {
				continue
			}

			let stations = try await resolveStations(for: target)

			for station in stations {
				await onProgress?(AutoSchedulePlanningStatus(message: "Predicting pass windows for \(target.name) at \(station.name)..."))
				let targetCandidates = try makeCandidates(
					target: target,
					targetIndex: targetIndex,
					tle: tle,
					station: station,
					start: start,
					end: end
				)
				candidates.append(contentsOf: targetCandidates)
			}
		}

		await onProgress?(AutoSchedulePlanningStatus(message: "Sorting predicted pass windows..."))
		let sortedCandidates = AutoSchedulePlanner.sortCandidates(candidates, priorityMode: priorityMode)
		await onProgress?(AutoSchedulePlanningStatus(message: "Fetching scheduled observations for selected ground stations..."))
		let existingObservations = try await fetchExistingObservations(
			for: sortedCandidates,
			start: start,
			end: end,
			onProgress: onProgress
		)
		await onProgress?(AutoSchedulePlanningStatus(message: "Filtering conflicts with existing and selected observations..."))
		let selection = AutoSchedulePlanner.selectNonConflictingCandidates(
			sortedCandidates,
			existingObservations: existingObservations
		)

		await onProgress?(AutoSchedulePlanningStatus(message: "Finalizing auto schedule plan..."))
		return AutoSchedulePlan(
			createdAt: Date(),
			start: start,
			end: end,
			priorityMode: priorityMode,
			candidates: candidates,
			selectedCandidates: selection.selected,
			skippedCandidates: selection.skipped,
			existingObservations: existingObservations
		)
	}

	private func makeCandidates(
		target: WatchTarget,
		targetIndex: Int,
		tle: TLEEntry,
		station: WatchStationSnapshot,
		start: Date,
		end: Date
	) throws -> [AutoScheduleCandidate] {
		let minimumElevation = max(
			0,
			target.minElevation ?? 0,
			station.minHorizon ?? 0
		)

		let passWindows = try passPredictor.predictPasses(
			tleName: tle.tle0,
			tleLine1: tle.tle1,
			tleLine2: tle.tle2,
			station: station,
			from: start,
			to: end,
			minimumElevation: minimumElevation
		)

		return passWindows.compactMap { passWindow in
			guard shouldIncludePassWindow(
				passWindow,
				target: target,
				station: station
			) else {
				return nil
			}

			let request = ObservationScheduleRequest(
				groundStationID: station.id,
				transmitterUUID: target.transmitterID,
				start: passWindow.start,
				end: passWindow.end
			)

			return AutoScheduleCandidate(
				target: target,
				targetIndex: targetIndex,
				station: station,
				passWindow: passWindow,
				request: request
			)
		}
	}

	static func sortCandidates(
		_ candidates: [AutoScheduleCandidate],
		priorityMode: AutoSchedulePriorityMode
	) -> [AutoScheduleCandidate] {
		candidates.sorted { lhs, rhs in
			switch priorityMode {
			case .watchListOrder:
				if lhs.targetIndex != rhs.targetIndex {
					return lhs.targetIndex < rhs.targetIndex
				}
				if lhs.request.start != rhs.request.start {
					return lhs.request.start < rhs.request.start
				}
				if lhs.peakElevation != rhs.peakElevation {
					return lhs.peakElevation > rhs.peakElevation
				}
				return lhs.duration > rhs.duration

			case .watchListOrderThenPeakElevation:
				if lhs.targetIndex != rhs.targetIndex {
					return lhs.targetIndex < rhs.targetIndex
				}
				if lhs.peakElevation != rhs.peakElevation {
					return lhs.peakElevation > rhs.peakElevation
				}
				if lhs.duration != rhs.duration {
					return lhs.duration > rhs.duration
				}
				return lhs.request.start < rhs.request.start

			case .peakElevationFirst:
				if lhs.peakElevation != rhs.peakElevation {
					return lhs.peakElevation > rhs.peakElevation
				}
				if lhs.duration != rhs.duration {
					return lhs.duration > rhs.duration
				}
				if lhs.targetIndex != rhs.targetIndex {
					return lhs.targetIndex < rhs.targetIndex
				}
				return lhs.request.start < rhs.request.start
			}
		}
	}

	static func selectNonConflictingCandidates(
		_ candidates: [AutoScheduleCandidate],
		existingObservations: [Observation]
	) -> (selected: [AutoScheduleCandidate], skipped: [AutoScheduleSkippedCandidate]) {
		var selected: [AutoScheduleCandidate] = []
		var skipped: [AutoScheduleSkippedCandidate] = []

		for candidate in candidates {
			if AutoSchedulePlanner.conflictsWithExistingObservation(candidate, existingObservations: existingObservations) {
				skipped.append(
					AutoScheduleSkippedCandidate(
						candidate: candidate,
						reason: .conflictWithExistingObservation,
						conflictingCandidate: nil
					)
				)
				continue
			}

			if let conflictingCandidate = selected.first(where: { AutoSchedulePlanner.conflicts(candidate, $0) }) {
				skipped.append(
					AutoScheduleSkippedCandidate(
						candidate: candidate,
						reason: .conflictWithSelected,
						conflictingCandidate: conflictingCandidate
					)
				)
				continue
			}

			selected.append(candidate)
		}

		return (selected, skipped)
	}

	private static func conflicts(_ lhs: AutoScheduleCandidate, _ rhs: AutoScheduleCandidate) -> Bool {
		lhs.request.groundStationID == rhs.request.groundStationID &&
		lhs.request.start < rhs.request.end &&
		rhs.request.start < lhs.request.end
	}

	private static func conflictsWithExistingObservation(
		_ candidate: AutoScheduleCandidate,
		existingObservations: [Observation]
	) -> Bool {
		existingObservations.contains { observation in
			AutoSchedulePlanner.conflicts(candidate, observation: observation)
		}
	}

	private static func conflicts(
		_ candidate: AutoScheduleCandidate,
		observation: Observation,
		conflictBuffer: TimeInterval = 5 * 60
	) -> Bool {
		guard candidate.request.groundStationID == observation.ground_station else {
			return false
		}

		guard let observationStart = observation.startDate,
			  let observationEnd = observation.endDate else {
			return false
		}

		let candidateStart = candidate.request.start.addingTimeInterval(-conflictBuffer)
		let candidateEnd = candidate.request.end.addingTimeInterval(conflictBuffer)
		return candidateStart < observationEnd && observationStart < candidateEnd
	}

	private func fetchExistingObservations(
		for candidates: [AutoScheduleCandidate],
		start: Date,
		end: Date,
		onProgress: ((AutoSchedulePlanningStatus) async -> Void)? = nil
	) async throws -> [Observation] {
		let stationNameByID = candidates.reduce(into: [Int: String]()) { result, candidate in
			let stationID = candidate.request.groundStationID
			guard result[stationID] == nil else {
				return
			}

			result[stationID] = candidate.stationName
		}
		let stationIDs = Array(stationNameByID.keys).sorted()
		guard !stationIDs.isEmpty else {
			return []
		}

		var observations: [Observation] = []

		for (index, stationID) in stationIDs.enumerated() {
			let stationName = stationNameByID[stationID] ?? "Station \(stationID)"
			await onProgress?(AutoSchedulePlanningStatus(message: "Fetching scheduled observations for \(stationName)..."))

			let stationObservations = try await networkService.fetchScheduledObservations(
				start: start,
				end: end,
				groundStationIDs: [stationID]
			)
			observations.append(contentsOf: stationObservations)

			StationScheduleStore.shared.replaceSchedule(
				with: stationObservations,
				groundStationIDs: [stationID]
			)

			if index < stationIDs.count - 1 {
				try? await Task.sleep(nanoseconds: 1_000_000_000)
			}
		}

		return observations
	}

	private func shouldIncludePassWindow(
		_ passWindow: PassWindow,
		target: WatchTarget,
		station: WatchStationSnapshot
	) -> Bool {
		if let minPeakElevation = target.minPeakElevation,
		   passWindow.peakElevation < minPeakElevation {
			return false
		}

		if let maxPeakElevation = target.maxPeakElevation,
		   passWindow.peakElevation > maxPeakElevation {
			return false
		}

		if !passesAzimuthFilter(passWindow, target: target) {
			return false
		}

		guard target.requiresStationDaylight else {
			return true
		}

		guard let latitude = station.latitude,
			  let longitude = station.longitude else {
			return false
		}

		let midpoint = passWindow.start.addingTimeInterval(
			passWindow.end.timeIntervalSince(passWindow.start) / 2
		)

		return SolarCalculator.isDaylight(
			date: midpoint,
			latitude: latitude,
			longitude: longitude
		)
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

	private func fetchTLEs(for targets: [WatchTarget]) async throws -> [String: TLEEntry] {
		let satelliteIDs = Array(Set(targets.map { $0.satelliteID })).sorted()
		guard !satelliteIDs.isEmpty else {
			return [:]
		}

		let entries = try await TLECacheStore.shared.fetchLatestTLEs(
			satelliteIDs: satelliteIDs
		)
		return Dictionary(uniqueKeysWithValues: entries.map { ($0.sat_id, $0) })
	}

	private func resolveStations(for target: WatchTarget) async throws -> [WatchStationSnapshot] {
		let cachedStations = target.stationSnapshots ?? [:]
		let cached = target.stationIDs.compactMap { cachedStations[$0] }

		if cached.count == target.stationIDs.count {
			return cached
		}

		let onlineStations = try await networkService.fetchOnlineStations()
		let stationMap = Dictionary(uniqueKeysWithValues: onlineStations.map { station in
			(
				station.id,
				WatchStationSnapshot(
					id: station.id,
					name: station.displayName,
					latitude: station.lat,
					longitude: station.lng,
					altitude: station.altitude,
					minHorizon: station.min_horizon
				)
			)
		})

		return target.stationIDs.compactMap { stationID in
			cachedStations[stationID] ?? stationMap[stationID]
		}
	}
}
