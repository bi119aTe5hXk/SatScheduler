//
//  Observation.swift
//  SatScheduler
//
//  Created by bi119aTe5hXk on 2026/05/16.
//

import Foundation

struct Observation: Codable, Identifiable, Hashable {
	let id: Int

	let start: String?
	let end: String?

	let ground_station: Int?
	let transmitter: String?
	let norad_cat_id: Int?
	let sat_id: String?
	let satellite_name: String?

	let payload: String?
	let waterfall: String?
	let demoddata: [DemodData]?

	let station_name: String?
	let station_lat: Double?
	let station_lng: Double?
	let station_alt: Double?
	
	let rise_azimuth: Double?
	let set_azimuth: Double?
	let max_altitude: Double?

	let vetted_status: String?
	let vetted_user: Int?
	let vetted_datetime: String?

	let archived: Bool?
	let archive_url: String?
	let client_version: String?
	let client_metadata: String?

	let status: String?
	let waterfall_status: String?
	let waterfall_status_user: Int?
	let waterfall_status_datetime: String?

	let transmitter_uuid: String?
	let transmitter_description: String?
	let transmitter_type: String?
	let transmitter_uplink_low: Int?
	let transmitter_uplink_high: Int?
	let transmitter_uplink_drift: Int?
	let transmitter_downlink_low: Int?
	let transmitter_downlink_high: Int?
	let transmitter_downlink_drift: Int?
	let transmitter_mode: String?
	let transmitter_invert: Bool?
	let transmitter_baud: Double?
	let transmitter_updated: String?
	let transmitter_status: String?
	let transmitter_unconfirmed: Bool?

	let tle0: String?
	let tle1: String?
	let tle2: String?
	let tle_source: String?

	let center_frequency: Int?
	let observer: String?
	let observation_frequency: Int?

	var startDate: Date? {
		Self.parseObservationDate(start)
	}

	var endDate: Date? {
		Self.parseObservationDate(end)
	}

	private static func parseObservationDate(_ string: String?) -> Date? {
		guard let string else {
			return nil
		}

		return observationDateFormatter.date(from: string)
			?? observationDateFormatterWithoutFractionalSeconds.date(from: string)
	}

	private static let observationDateFormatter: ISO8601DateFormatter = {
		let formatter = ISO8601DateFormatter()
		formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
		return formatter
	}()

	private static let observationDateFormatterWithoutFractionalSeconds: ISO8601DateFormatter = {
		let formatter = ISO8601DateFormatter()
		formatter.formatOptions = [.withInternetDateTime]
		return formatter
	}()

	var audio: String? {
		payload
	}

	var stationDisplayName: String {
		station_name ?? ground_station.map { "Station \($0)" } ?? "Station"
	}

	var transmitterDisplayName: String {
		transmitter_description ?? transmitter_uuid ?? transmitter ?? "Transmitter"
	}

	var statusDisplayText: String {
		status ?? "unknown"
	}

	var vettedStatusDisplayText: String {
		vetted_status ?? "unknown"
	}

	var maxAltitudeText: String {
		guard let max_altitude else {
			return "-"
		}

		return String(format: "%.0f°", max_altitude)
	}

	var frequencyText: String {
		let frequency = observation_frequency ?? transmitter_downlink_low ?? center_frequency

		guard let frequency else {
			return "-"
		}

		return String(format: "%.3f MHz", Double(frequency) / 1_000_000.0)
	}
}

struct DemodData: Codable, Hashable {
	let payload: String?
	let frame: String?
	let observer: String?
	let station: Int?
	let timestamp: String?
}
