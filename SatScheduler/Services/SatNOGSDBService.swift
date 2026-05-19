//
//  SatNOGSDBService.swift
//  SatScheduler
//
//  Created by bi119aTe5hXk on 2026/05/16.
//

import Foundation

final class SatNOGSDBService {

	private let client: SatNOGSAPIClient

	init(client: SatNOGSAPIClient = .shared) {
		self.client = client
	}

	func fetchAliveSatellites() async throws -> [SatelliteModel] {
		try await client.get(
			host: .db,
			path: "satellites/",
			queryItems: [
				URLQueryItem(name: "status", value: "alive")
			]
		)
	}

	func fetchTransmitters(satelliteID: String) async throws -> [Transmitter] {
		let transmitters: [Transmitter] = try await client.get(
			host: .db,
			path: "transmitters/",
			queryItems: [
				URLQueryItem(name: "sat_id", value: satelliteID)
			]
		)

		let filteredTransmitters = transmitters.filter { transmitter in
			transmitter.sat_id == satelliteID && transmitter.status == "active"
		}

		return filteredTransmitters.isEmpty
			? transmitters.filter { $0.sat_id == satelliteID }
			: filteredTransmitters
	}

	func fetchTLEEntries(satelliteID: String) async throws -> [TLEEntry] {
		try await client.get(
			host: .db,
			path: "tle/",
			queryItems: [
				URLQueryItem(name: "sat_id", value: satelliteID)
			]
		)
	}

	func fetchTLEEntries(satelliteIDs: [String]) async throws -> [TLEEntry] {
		let uniqueSatelliteIDs = Array(Set(satelliteIDs)).sorted()
		guard !uniqueSatelliteIDs.isEmpty else {
			return []
		}

		return try await client.get(
			host: .db,
			path: "tle/",
			queryItems: [
				URLQueryItem(name: "sat_id", value: uniqueSatelliteIDs.joined(separator: ","))
			]
		)
	}

	func fetchLatestTLE(satelliteID: String) async throws -> TLEEntry? {
		let entries = try await fetchTLEEntries(satelliteID: satelliteID)

		return entries
			.filter { $0.sat_id == satelliteID }
			.sorted { lhs, rhs in
				guard let lhsDate = lhs.updatedDate else {
					return false
				}

				guard let rhsDate = rhs.updatedDate else {
					return true
				}

				return lhsDate > rhsDate
			}
			.first
	}

	func fetchLatestTLEs(satelliteIDs: [String]) async throws -> [TLEEntry] {
		let entries = try await fetchTLEEntries(satelliteIDs: satelliteIDs)
		let requestedIDs = Set(satelliteIDs)
		let groupedEntries = Dictionary(grouping: entries.filter { requestedIDs.contains($0.sat_id) }) { entry in
			entry.sat_id
		}

		return groupedEntries.values.compactMap { entries in
			entries.sorted { lhs, rhs in
				guard let lhsDate = lhs.updatedDate else {
					return false
				}

				guard let rhsDate = rhs.updatedDate else {
					return true
				}

				return lhsDate > rhsDate
			}
			.first
		}
	}
}


