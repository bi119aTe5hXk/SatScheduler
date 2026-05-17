//
//  ObservationScheduleConflictResolver.swift
//  SatScheduler
//
//  Created by bi119aTe5hXk on 2026/05/16.
//

import Foundation

struct ObservationScheduleConflictResult {
	let allowedRequests: [ObservationScheduleRequest]
	let skippedRequests: [SkippedObservationScheduleRequest]

	var hasSkippedRequests: Bool {
		!skippedRequests.isEmpty
	}
}

struct SkippedObservationScheduleRequest: Identifiable, Hashable {
	let id = UUID()
	let request: ObservationScheduleRequest
	let reason: String
	let conflictingObservationID: Int?
}



enum ObservationScheduleConflictResolver {
	static func filterConflicts(
		requests: [ObservationScheduleRequest],
		existingObservations: [Observation],
		conflictBuffer: TimeInterval = 0
	) -> ObservationScheduleConflictResult {
		let existingIntervals = existingObservations.compactMap(Self.makeExistingInterval)
		var intervalsByStation = Dictionary(grouping: existingIntervals) { $0.stationID }

		var allowed: [ObservationScheduleRequest] = []
		var skipped: [SkippedObservationScheduleRequest] = []

		let sortedRequests = requests.sorted {
			if $0.groundStationID == $1.groundStationID {
				return $0.startDate < $1.startDate
			}
			return $0.groundStationID < $1.groundStationID
		}

		print("Conflict check: \(sortedRequests.count) request(s), \(existingIntervals.count) existing future observation interval(s).")

		for request in sortedRequests {
			let requestStart = request.startDate
			let requestEnd = request.endDate

			guard requestStart < requestEnd else {
				skipped.append(
					SkippedObservationScheduleRequest(
						request: request,
						reason: "Invalid request time range",
						conflictingObservationID: nil
					)
				)
				continue
			}

			let stationIntervals = intervalsByStation[request.groundStationID] ?? []
			var conflictInterval: ExistingObservationInterval?

			for existingInterval in stationIntervals {
				if overlaps(
					requestStart: requestStart,
					requestEnd: requestEnd,
					existingStart: existingInterval.start,
					existingEnd: existingInterval.end,
					buffer: conflictBuffer
				) {
					conflictInterval = existingInterval
					break
				}
			}

			if let conflictInterval {
				let reason = conflictInterval.observationID.map {
					"Overlaps with existing observation \($0)"
				} ?? "Overlaps with another requested observation"

				print("Skip request station=\(request.groundStationID), start=\(requestStart), end=\(requestEnd), reason=\(reason)")

				skipped.append(
					SkippedObservationScheduleRequest(
						request: request,
						reason: reason,
						conflictingObservationID: conflictInterval.observationID
					)
				)
			} else {
				allowed.append(request)
				
				print("Add request station=\(request.groundStationID), start=\(requestStart), end=\(requestEnd)")

				intervalsByStation[request.groundStationID, default: []].append(
					ExistingObservationInterval(
						observationID: nil,
						stationID: request.groundStationID,
						start: requestStart,
						end: requestEnd
					)
				)
			}
		}

		print("Conflict check result: allowed \(allowed.count), skipped \(skipped.count).")

		return ObservationScheduleConflictResult(
			allowedRequests: allowed,
			skippedRequests: skipped
		)
	}

	private static func overlaps(
		requestStart: Date,
		requestEnd: Date,
		existingStart: Date,
		existingEnd: Date,
		buffer: TimeInterval
	) -> Bool {
		let bufferedRequestStart = requestStart.addingTimeInterval(-buffer)
		let bufferedRequestEnd = requestEnd.addingTimeInterval(buffer)

		return bufferedRequestStart < existingEnd && existingStart < bufferedRequestEnd
	}

	private static func makeExistingInterval(from observation: Observation) -> ExistingObservationInterval? {
		guard let stationID = observation.ground_station,
			  let startString = observation.start,
			  let endString = observation.end,
			  let start = parseObservationDate(startString),
			  let end = parseObservationDate(endString),
			  start < end else {
			print("Skip existing observation because time parse failed or range is invalid: id=\(observation.id), station=\(String(describing: observation.ground_station)), start=\(String(describing: observation.start)), end=\(String(describing: observation.end))")
			return nil
		}

		return ExistingObservationInterval(
			observationID: observation.id,
			stationID: stationID,
			start: start,
			end: end
		)
	}

	private static func parseObservationDate(_ string: String) -> Date? {
		if let date = SatNOGSNetworkService.observationDateFormatter.date(from: string) {
			return date
		}

		if let date = SatNOGSNetworkService.isoFormatter.date(from: string) {
			return date
		}

		let formatters: [DateFormatter] = [
			makeFormatter("yyyy-MM-dd'T'HH:mm:ss.SSSSSSXXXXX"),
			makeFormatter("yyyy-MM-dd'T'HH:mm:ss.SSSXXXXX"),
			makeFormatter("yyyy-MM-dd'T'HH:mm:ssXXXXX"),
			makeFormatter("yyyy-MM-dd HH:mm:ss.SSSSSS"),
			makeFormatter("yyyy-MM-dd HH:mm:ss")
		]

		for formatter in formatters {
			if let date = formatter.date(from: string) {
				return date
			}
		}

		return nil
	}

	private static func makeFormatter(_ format: String) -> DateFormatter {
		let formatter = DateFormatter()
		formatter.locale = Locale(identifier: "en_US_POSIX")
		formatter.timeZone = TimeZone(secondsFromGMT: 0)
		formatter.dateFormat = format
		return formatter
	}

	private struct ExistingObservationInterval {
		let observationID: Int?
		let stationID: Int
		let start: Date
		let end: Date
	}
}
