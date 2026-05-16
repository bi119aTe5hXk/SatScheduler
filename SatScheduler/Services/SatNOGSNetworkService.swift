//
//  SatNOGSNetworkService.swift
//  SatScheduler
//
//  Created by bi119aTe5hXk on 2026/05/16.
//


import Foundation

struct ObservationScheduleRequest: Encodable, Hashable {

	let groundStationID: Int
	let transmitterUUID: String
	let start: Date
	let end: Date
	enum CodingKeys: String, CodingKey {
		case groundStationID = "ground_station"
		case transmitterUUID = "transmitter_uuid"
		case start
		case end
	}
	func encode(to encoder: Encoder) throws {
		var container = encoder.container(keyedBy: CodingKeys.self)
		try container.encode(groundStationID, forKey: .groundStationID)
		try container.encode(transmitterUUID, forKey: .transmitterUUID)
		try container.encode(SatNOGSNetworkService.observationDateFormatter.string(from: start), forKey: .start)
		try container.encode(SatNOGSNetworkService.observationDateFormatter.string(from: end), forKey: .end)
	}


}

extension ObservationScheduleRequest {
	var startDate: Date {
		start
	}

	var endDate: Date {
		end
	}
}

final class SatNOGSNetworkService {

	private let client: SatNOGSAPIClient

	init(client: SatNOGSAPIClient = .shared) {
		self.client = client
	}
	
	// MARK: - Stations

	func fetchOnlineStations(
		id: Int? = nil,
		name: String? = nil
	) async throws -> [GroundStation] {
		var items: [URLQueryItem] = [
			URLQueryItem(name: "id", value: id.map(String.init) ?? ""),
			URLQueryItem(name: "name", value: name ?? ""),
			URLQueryItem(name: "status", value: "2")
		]

		return try await client.get(
			host: .networkAPI,
			path: "stations/",
			queryItems: items
		)
	}

	// MARK: - Observations
	
	func fetchUnknownObservations(
		observerID: Int
	) async throws -> [Observation] {

		try await client.get(
			host: .networkAPI,
			path: "observations/",
			queryItems: [
				URLQueryItem(name: "status", value: "unknown"),
				URLQueryItem(name: "observer", value: String(observerID))
			],
			requiresToken: true
		)
	}
	
	func fetchObservations(
		groundStationID: Int? = nil,
		observerID: Int? = nil,
		future: Bool? = nil
	) async throws -> [Observation] {

		var items: [URLQueryItem] = []

		if let groundStationID {
			items.append(URLQueryItem(
				name: "ground_station",
				value: String(groundStationID)
			))
		}

		if let observerID {
			items.append(URLQueryItem(
				name: "observer",
				value: String(observerID)
			))
		}

		if let future {
			items.append(URLQueryItem(
				name: "future",
				value: future ? "1" : "0"
			))
		}

		return try await client.get(
			host: .networkAPI,
			path: "observations/",
			queryItems: items,
			requiresToken: true
		)
	}

	func fetchScheduledObservations(
		start: Date,
		end: Date,
		groundStationIDs: [Int] = []
	) async throws -> [Observation] {
		guard !groundStationIDs.isEmpty else {
			throw APIError.parameterError
		}

		var observations: [Observation] = []

		for groundStationID in groundStationIDs {
			let stationItems: [URLQueryItem] = [
				URLQueryItem(name: "status", value: "future"),
				URLQueryItem(name: "ground_station", value: String(groundStationID))
			]

			let stationObservations: [Observation] = try await client.get(
				host: .networkAPI,
				path: "observations/",
				queryItems: stationItems,
				requiresToken: true
			)

			print("Fetched \(stationObservations.count) future observation(s) for station \(groundStationID)")
			observations.append(contentsOf: stationObservations)
		}

		return observations
	}
	private static func parseObservationDate(_ string: String) -> Date? {
		if let date = observationDateFormatter.date(from: string) {
			return date
		}

		if let date = isoFormatter.date(from: string) {
			return date
		}

		let fallbackFormatter = DateFormatter()
		fallbackFormatter.locale = Locale(identifier: "en_US_POSIX")
		fallbackFormatter.timeZone = TimeZone(secondsFromGMT: 0)
		fallbackFormatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ssXXXXX"
		return fallbackFormatter.date(from: string)
	}

	func createObservation(
		groundStationID: Int,
		transmitterID: String,
		start: Date,
		end: Date
	) async throws -> Observation {

		let body = CreateObservationRequest(
			ground_station: groundStationID,
			transmitter_uuid: transmitterID,
			start: Self.observationDateFormatter.string(from: start),
			end: Self.observationDateFormatter.string(from: end)
		)

		return try await client.postJSON(
			host: .networkAPI,
			path: "observations/",
			body: body,
			requiresToken: true
		)
	}

	func createObservations(_ requests: [ObservationScheduleRequest]) async throws -> [Observation] {
		guard !requests.isEmpty else {
			return []
		}

		let observations: [Observation] = try await client.postJSON(
			host: .networkAPI,
			path: "observations/",
			body: requests,
			requiresToken: true
		)

		StationScheduleStore.shared.mergeCreatedObservations(observations)
		return observations
	}

	private struct CreateObservationRequest: Encodable {
		let ground_station: Int
		let transmitter_uuid: String
		let start: String
		let end: String
	}

	// MARK: - Formatters

	private static let predictionDateFormatter: DateFormatter = {
		let formatter = DateFormatter()
		formatter.dateFormat = "yyyy-MM-dd HH:mm"
		formatter.timeZone = TimeZone(secondsFromGMT: 0)
		formatter.locale = Locale(identifier: "en_US_POSIX")
		return formatter
	}()

	static let observationDateFormatter: DateFormatter = {
		let formatter = DateFormatter()
		formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
		formatter.timeZone = TimeZone(secondsFromGMT: 0)
		formatter.locale = Locale(identifier: "en_US_POSIX")
		return formatter
	}()

	static let isoFormatter: ISO8601DateFormatter = {
		let formatter = ISO8601DateFormatter()
		formatter.formatOptions = [
			.withInternetDateTime
		]
		return formatter
	}()
}
