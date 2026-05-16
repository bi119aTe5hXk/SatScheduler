//
//  PredictionWindow.swift
//  SatScheduler
//
//  Created by bi119aTe5hXk on 2026/05/16.
//

import Foundation

struct PredictionStationWindow: Codable, Identifiable, Hashable {
	let id: Int
	let name: String?
	let status: Int?
	let lng: Double?
	let lat: Double?
	let alt: Double?
	let window: [PredictionWindow]

	var stationID: Int {
		id
	}
}

struct PredictionWindow: Codable, Identifiable, Hashable {
	let start: String
	let end: String
	let az_start: Double?
	let az_end: Double?
	let elev_max: Double?
	let tle0: String?
	let tle1: String?
	let tle2: String?
	let valid_duration: Bool?
	let overlapped: Bool?
	let split: Bool?
	let overlap_ratio: Double?

	var id: String {
		"\(start)-\(end)-\(elev_max ?? 0)"
	}

	var maxElevationText: String {
		guard let elev_max else {
			return "-"
		}

		return String(format: "%.0f°", elev_max)
	}

	var azimuthText: String {
		let startText: String
		if let az_start {
			startText = String(format: "%.0f°", az_start)
		} else {
			startText = "-"
		}

		let endText: String
		if let az_end {
			endText = String(format: "%.0f°", az_end)
		} else {
			endText = "-"
		}

		return "\(startText) → \(endText)"
	}

	var isAvailable: Bool {
		(valid_duration ?? false) && !(overlapped ?? false)
	}
}
