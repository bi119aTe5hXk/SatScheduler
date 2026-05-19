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

enum ObservationVettedStatus: String, CaseIterable, Identifiable, Codable {
	case unknown
	case bad
	case good

	var id: String {
		rawValue
	}

	var displayName: String {
		switch self {
		case .unknown:
			return "Unknown"
		case .bad:
			return "Bad"
		case .good:
			return "Good"
		}
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
		let items: [URLQueryItem] = [
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
		try await fetchAllObservationPages(
			queryItems: [
				URLQueryItem(name: "status", value: "unknown"),
				URLQueryItem(name: "observer", value: String(observerID))
			],
			logPrefix: "unknown observations for observer \(observerID)"
		)
	}
	
	func fetchGoodObservations(
		noradCatID: Int,
		maxPages: Int = 3
	) async throws -> [Observation] {
		try await fetchObservationPages(
			queryItems: [
				URLQueryItem(name: "status", value: "good"),
				URLQueryItem(name: "norad_cat_id", value: String(noradCatID))
			],
			maxPages: maxPages,
			logPrefix: "good observations for NORAD \(noradCatID)"
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

		return try await fetchAllObservationPages(
			queryItems: items,
			logPrefix: "observations"
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

			let stationObservations = try await fetchAllObservationPages(
				queryItems: stationItems,
				logPrefix: "future observations for station \(groundStationID)"
			)

			observations.append(contentsOf: stationObservations)
			print("Fetched \(stationObservations.count) future observation(s) for station \(groundStationID)")
		}

		return observations
	}

	private func fetchAllObservationPages(
		queryItems: [URLQueryItem],
		logPrefix: String
	) async throws -> [Observation] {
		try await fetchObservationPages(
			queryItems: queryItems,
			maxPages: nil,
			logPrefix: logPrefix
		)
	}

	private func fetchObservationPages(
		queryItems: [URLQueryItem],
		maxPages: Int?,
		logPrefix: String
	) async throws -> [Observation] {
		var observations: [Observation] = []
		var nextCursor: String?
		var seenCursors = Set<String>()
		var fetchedPageCount = 0

		repeat {
			if let maxPages, fetchedPageCount >= maxPages {
				break
			}

			var pageItems = queryItems

			if let nextCursor {
				guard !seenCursors.contains(nextCursor) else {
					break
				}
				seenCursors.insert(nextCursor)
				pageItems.append(URLQueryItem(name: "cursor", value: nextCursor))
			}

			let page: ObservationListResponse = try await client.get(
				host: .networkAPI,
				path: "observations/",
				queryItems: pageItems,
				requiresToken: false
			)

			fetchedPageCount += 1
			observations.append(contentsOf: page.results)

			let resolvedNextCursor = page.nextCursor ?? Self.fallbackNextCursor(from: page.results)
			if let resolvedNextCursor, seenCursors.contains(resolvedNextCursor) {
				nextCursor = nil
			} else {
				nextCursor = resolvedNextCursor
			}

			print("Fetched page \(fetchedPageCount) for \(logPrefix): \(page.results.count) observation(s), nextCursor: \(nextCursor ?? "nil")")
			
			if nextCursor != nil {
				try? await Task.sleep(nanoseconds: 1_000_000_000)
			}
		} while nextCursor != nil

		return observations
	}

	private static func fallbackNextCursor(from observations: [Observation]) -> String? {
		guard observations.count >= 25,
			  let lastObservation = observations.last,
			  let startString = lastObservation.start,
			  let startDate = parseObservationDate(startString) else {
			return nil
		}

		let position = cursorDateFormatter.string(from: startDate)
		let encodedPosition = position
			.replacingOccurrences(of: "+", with: "%2B")
			.replacingOccurrences(of: " ", with: "+")
			.replacingOccurrences(of: ":", with: "%3A")

		return Data("p=\(encodedPosition)".utf8).base64EncodedString()
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

	func updateObservationVettedStatus(
		observationID: Int,
		status: ObservationVettedStatus
	) async throws -> Observation {
		let body = UpdateObservationVettedStatusRequest(
			vetted_status: status.rawValue
		)

		return try await client.patchJSON(
			host: .networkAPI,
			path: "observations/\(observationID)/",
			body: body,
			requiresToken: true
		)
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
	
	private struct ObservationListResponse: Decodable {
		let results: [Observation]
		let nextCursor: String?

		private enum CodingKeys: String, CodingKey {
			case results
			case next
		}

		init(from decoder: Decoder) throws {
			if let arrayContainer = try? decoder.singleValueContainer(),
			   let observations = try? arrayContainer.decode([Observation].self) {
				results = observations
				nextCursor = nil
				return
			}

			let container = try decoder.container(keyedBy: CodingKeys.self)
			results = try container.decode([Observation].self, forKey: .results)

			let nextURLString = try container.decodeIfPresent(String.self, forKey: .next)
			nextCursor = Self.cursorValue(from: nextURLString)
		}

		private static func cursorValue(from nextURLString: String?) -> String? {
			guard let nextURLString,
				  let components = URLComponents(string: nextURLString) else {
				return nil
			}

			return components.queryItems?.first(where: { $0.name == "cursor" })?.value
		}
	}

	private struct CreateObservationRequest: Encodable {
		let ground_station: Int
		let transmitter_uuid: String
		let start: String
		let end: String
	}

	private struct UpdateObservationVettedStatusRequest: Encodable {
		let vetted_status: String
	}

	// MARK: - Formatters

	private static let predictionDateFormatter: DateFormatter = {
		let formatter = DateFormatter()
		formatter.dateFormat = "yyyy-MM-dd HH:mm"
		formatter.timeZone = TimeZone(secondsFromGMT: 0)
		formatter.locale = Locale(identifier: "en_US_POSIX")
		return formatter
	}()

	private static let cursorDateFormatter: DateFormatter = {
		let formatter = DateFormatter()
		formatter.dateFormat = "yyyy-MM-dd HH:mm:ssXXXXX"
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
