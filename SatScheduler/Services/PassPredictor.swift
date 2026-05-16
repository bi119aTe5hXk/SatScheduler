//
//  PassPredictor.swift
//  SatScheduler
//
//  Created by bi119aTe5hXk on 2026/05/16.
//

import Foundation
import SatelliteKit

struct PassWindow: Identifiable, Hashable {
	let start: Date
	let end: Date
	let maxElevation: Double
	let azimuthStart: Double
	let azimuthEnd: Double

	var id: String {
		"\(start.timeIntervalSince1970)-\(end.timeIntervalSince1970)-\(maxElevation)"
	}
}

enum PassPredictorError: LocalizedError {
	case invalidStationLocation
	case invalidTLE
	case emptyDateRange

	var errorDescription: String? {
		switch self {
		case .invalidStationLocation:
			return "Ground station latitude or longitude is missing."
		case .invalidTLE:
			return "TLE data is invalid."
		case .emptyDateRange:
			return "Prediction end date must be later than start date."
		}
	}
}

final class PassPredictor {
	private static let minimumObservationDuration: TimeInterval = 180
	private static let minimumScheduleLeadTime: TimeInterval = 5 * 60

	private let scanStep: TimeInterval
	private let refineIterations: Int

	init(scanStep: TimeInterval = 30, refineIterations: Int = 10) {
		self.scanStep = scanStep
		self.refineIterations = refineIterations
	}

	func predictPasses(
		elements: Elements,
		station: WatchStationSnapshot,
		from startDate: Date,
		to endDate: Date,
		minimumElevation: Double? = nil
	) throws -> [PassWindow] {
		let earliestAllowedStartDate = Date().addingTimeInterval(Self.minimumScheduleLeadTime)
		let effectiveStartDate = max(startDate, earliestAllowedStartDate)

		guard endDate > effectiveStartDate else {
			throw PassPredictorError.emptyDateRange
		}

		guard let latitude = station.latitude,
			  let longitude = station.longitude else {
			throw PassPredictorError.invalidStationLocation
		}

		let minElevation = minimumRequiredElevation(
			minimumElevation: minimumElevation,
			stationMinHorizon: station.minHorizon
		)
		let altitudeKm = (station.altitude ?? 0) / 1_000.0
		let observer = LatLonAlt(latitude, longitude, altitudeKm)
		let satellite = Satellite(elements: elements)

		var passes: [PassWindow] = []
		var currentDate = effectiveStartDate
		var previousSample = try sample(satellite: satellite, observer: observer, elements: elements, date: currentDate)
		var activePass: ActivePass?

		if previousSample.elevation >= minElevation {
			activePass = ActivePass(start: previousSample, maxSample: previousSample)
		}

		while currentDate < endDate {
			let nextDate = min(currentDate.addingTimeInterval(scanStep), endDate)
			let nextSample = try sample(satellite: satellite, observer: observer, elements: elements, date: nextDate)

			if activePass == nil,
			   previousSample.elevation < minElevation,
			   nextSample.elevation >= minElevation {
				let aos = try refineCrossing(
					satellite: satellite,
					observer: observer,
					elements: elements,
					from: previousSample,
					to: nextSample,
					minimumElevation: minElevation
				)
				activePass = ActivePass(start: aos, maxSample: nextSample)
			}

			if var pass = activePass {
				if nextSample.elevation > pass.maxSample.elevation {
					pass.maxSample = nextSample
				}

				if previousSample.elevation >= minElevation,
				   nextSample.elevation < minElevation {
					let los = try refineCrossing(
						satellite: satellite,
						observer: observer,
						elements: elements,
						from: previousSample,
						to: nextSample,
						minimumElevation: minElevation
					)

					let passWindow = PassWindow(
						start: pass.start.date,
						end: los.date,
						maxElevation: pass.maxSample.elevation,
						azimuthStart: pass.start.azimuth,
						azimuthEnd: los.azimuth
					)

					if shouldIncludePass(
						passWindow,
						earliestAllowedStartDate: earliestAllowedStartDate,
						minimumElevation: minElevation
					) {
						passes.append(passWindow)
					}

					activePass = nil
				} else {
					activePass = pass
				}
			}

			previousSample = nextSample
			currentDate = nextDate
		}

		return passes
	}

	func predictPasses(
		tleName: String?,
		tleLine1: String,
		tleLine2: String,
		station: WatchStationSnapshot,
		from startDate: Date,
		to endDate: Date,
		minimumElevation: Double? = nil
	) throws -> [PassWindow] {
		try predictPasses(
			tleName: tleName,
			tleLine1: tleLine1,
			tleLine2: tleLine2,
			latitude: station.latitude,
			longitude: station.longitude,
			altitude: station.altitude,
			minHorizon: station.minHorizon,
			from: startDate,
			to: endDate,
			minimumElevation: minimumElevation
		)
	}

	func predictPasses(
		tleName: String?,
		tleLine1: String,
		tleLine2: String,
		station: GroundStation,
		from startDate: Date,
		to endDate: Date,
		minimumElevation: Double? = nil
	) throws -> [PassWindow] {
		try predictPasses(
			tleName: tleName,
			tleLine1: tleLine1,
			tleLine2: tleLine2,
			latitude: station.lat,
			longitude: station.lng,
			altitude: station.altitude,
			minHorizon: station.min_horizon,
			from: startDate,
			to: endDate,
			minimumElevation: minimumElevation
		)
	}

	private func predictPasses(
		tleName: String?,
		tleLine1: String,
		tleLine2: String,
		latitude: Double?,
		longitude: Double?,
		altitude: Double?,
		minHorizon: Double?,
		from startDate: Date,
		to endDate: Date,
		minimumElevation: Double? = nil
	) throws -> [PassWindow] {
		let earliestAllowedStartDate = Date().addingTimeInterval(Self.minimumScheduleLeadTime)
		let effectiveStartDate = max(startDate, earliestAllowedStartDate)

		guard endDate > effectiveStartDate else {
			throw PassPredictorError.emptyDateRange
		}

		guard let latitude, let longitude else {
			throw PassPredictorError.invalidStationLocation
		}

		let minElevation = minimumRequiredElevation(
			minimumElevation: minimumElevation,
			stationMinHorizon: minHorizon
		)
		let altitudeKm = (altitude ?? 0) / 1_000.0
		let observer = LatLonAlt(latitude, longitude, altitudeKm)

		let satellite: Satellite
		let elements: Elements
		do {
			elements = try Elements(tleName ?? "", tleLine1, tleLine2)
			satellite = Satellite(elements: elements)
		} catch {
			throw PassPredictorError.invalidTLE
		}

		var passes: [PassWindow] = []
		var currentDate = effectiveStartDate
		var previousSample = try sample(satellite: satellite, observer: observer, elements: elements, date: currentDate)
		var activePass: ActivePass?

		if previousSample.elevation >= minElevation {
			activePass = ActivePass(start: previousSample, maxSample: previousSample)
		}

		while currentDate < endDate {
			let nextDate = min(currentDate.addingTimeInterval(scanStep), endDate)
			let nextSample = try sample(satellite: satellite, observer: observer, elements: elements, date: nextDate)

			if activePass == nil,
			   previousSample.elevation < minElevation,
			   nextSample.elevation >= minElevation {
				let aos = try refineCrossing(
					satellite: satellite,
					observer: observer,
					elements: elements,
					from: previousSample,
					to: nextSample,
					minimumElevation: minElevation
				)
				activePass = ActivePass(start: aos, maxSample: nextSample)
			}

			if var pass = activePass {
				if nextSample.elevation > pass.maxSample.elevation {
					pass.maxSample = nextSample
				}

				if previousSample.elevation >= minElevation,
				   nextSample.elevation < minElevation {
					let los = try refineCrossing(
						satellite: satellite,
						observer: observer,
						elements: elements,
						from: previousSample,
						to: nextSample,
						minimumElevation: minElevation
					)

					let passWindow = PassWindow(
						start: pass.start.date,
						end: los.date,
						maxElevation: pass.maxSample.elevation,
						azimuthStart: pass.start.azimuth,
						azimuthEnd: los.azimuth
					)

					if shouldIncludePass(
						passWindow,
						earliestAllowedStartDate: earliestAllowedStartDate,
						minimumElevation: minElevation
					) {
						passes.append(passWindow)
					}

					activePass = nil
				} else {
					activePass = pass
				}
			}

			previousSample = nextSample
			currentDate = nextDate
		}

		return passes
	}

	private func minimumRequiredElevation(
		minimumElevation: Double?,
		stationMinHorizon: Double?
	) -> Double {
		max(0, minimumElevation ?? 0, stationMinHorizon ?? 0)
	}

	private func sample(
		satellite: Satellite,
		observer: LatLonAlt,
		elements: Elements,
		date: Date
	) throws -> PassSample {
		let minutesAfterEpoch = (date.julianDaysSince1950 - elements.t₀) * 1_440.0
		let topocentric = try satellite.topPosition(minsAfterEpoch: minutesAfterEpoch, observer: observer)

		return PassSample(
			date: date,
			elevation: topocentric.elev,
			azimuth: normalizedDegrees(topocentric.azim)
		)
	}

	private func refineCrossing(
		satellite: Satellite,
		observer: LatLonAlt,
		elements: Elements,
		from lowSample: PassSample,
		to highSample: PassSample,
		minimumElevation: Double
	) throws -> PassSample {
		var lower = lowSample
		var upper = highSample

		for _ in 0..<refineIterations {
			let midpointDate = Date(timeIntervalSince1970: (lower.date.timeIntervalSince1970 + upper.date.timeIntervalSince1970) / 2.0)
			let midpoint = try sample(satellite: satellite, observer: observer, elements: elements, date: midpointDate)

			if (lower.elevation < minimumElevation && midpoint.elevation < minimumElevation) ||
			   (lower.elevation >= minimumElevation && midpoint.elevation >= minimumElevation) {
				lower = midpoint
			} else {
				upper = midpoint
			}
		}

		return upper.elevation >= minimumElevation ? upper : lower
	}

	private func normalizedDegrees(_ degrees: Double) -> Double {
		let value = degrees.truncatingRemainder(dividingBy: 360)
		return value >= 0 ? value : value + 360
	}
	private func shouldIncludePass(
		_ passWindow: PassWindow,
		earliestAllowedStartDate: Date,
		minimumElevation: Double
	) -> Bool {
		guard passWindow.start >= earliestAllowedStartDate else {
			return false
		}

		let duration = passWindow.end.timeIntervalSince(passWindow.start)
		guard duration >= Self.minimumObservationDuration else {
			return false
		}

		guard passWindow.maxElevation >= minimumElevation else {
			return false
		}

		return true
	}
}

private struct PassSample: Hashable {
	let date: Date
	let elevation: Double
	let azimuth: Double
}

private struct ActivePass {
	let start: PassSample
	var maxSample: PassSample
}

private extension Date {
	var julianDaysSince1950: Double {
		let reference = DateComponents(
			calendar: Calendar(identifier: .gregorian),
			timeZone: TimeZone(secondsFromGMT: 0),
			year: 1950,
			month: 1,
			day: 0,
			hour: 0,
			minute: 0,
			second: 0
		).date!

		return timeIntervalSince(reference) / 86_400.0
	}
}
