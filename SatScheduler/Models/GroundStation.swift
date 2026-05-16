//
//  GroundStation.swift
//  SatScheduler
//
import Foundation

struct GroundStation: Codable, Identifiable, Hashable {
	let id: Int
	let name: String?
	let altitude: Double?
	let min_horizon: Double?
	let lat: Double?
	let lng: Double?
	let qthlocator: String?
	let antenna: [GroundStationAntenna]?
	let created: String?
	let last_seen: String?
	let status: String?
	let observations: Int?
	let future_observations: Int?
	let description: String?
	let client_version: String?
	let target_utilization: Int?
	let image: String?
	let success_rate: FlexibleInt?
	let owner: String?

	var displayName: String {
		name ?? "Station \(id)"
	}

	var altitudeText: String {
		guard let altitude else {
			return "-"
		}
		return "\(Int(altitude)) m"
	}

	var antennaText: String {
		guard let antenna, !antenna.isEmpty else {
			return "-"
		}

		return antenna.map { item in
			if let band = item.band, let typeName = item.antenna_type_name {
				return "\(band) / \(typeName)"
			}
			if let band = item.band {
				return band
			}
			if let typeName = item.antenna_type_name {
				return typeName
			}
			return "Antenna"
		}
		.joined(separator: ", ")
	}

	var successRateValue: Int? {
		success_rate?.intValue
	}
}

struct GroundStationAntenna: Codable, Hashable {
	let frequency: Int?
	let frequency_max: Int?
	let band: String?
	let antenna_type: String?
	let antenna_type_name: String?

	var frequencyRangeText: String {
		guard let frequency else {
			return "-"
		}

		let startMHz = Double(frequency) / 1_000_000.0

		if let frequency_max {
			let endMHz = Double(frequency_max) / 1_000_000.0
			return String(format: "%.0f-%.0f MHz", startMHz, endMHz)
		}

		return String(format: "%.0f MHz", startMHz)
	}
}

struct FlexibleInt: Codable, Hashable {
	let intValue: Int?

	init(from decoder: Decoder) throws {
		let container = try decoder.singleValueContainer()

		if container.decodeNil() {
			self.intValue = nil
		} else if let intValue = try? container.decode(Int.self) {
			self.intValue = intValue
		} else if let doubleValue = try? container.decode(Double.self) {
			self.intValue = Int(doubleValue)
		} else if let boolValue = try? container.decode(Bool.self) {
			self.intValue = boolValue ? 1 : nil
		} else if let stringValue = try? container.decode(String.self),
				  let intValue = Int(stringValue) {
			self.intValue = intValue
		} else {
			self.intValue = nil
		}
	}

	func encode(to encoder: Encoder) throws {
		var container = encoder.singleValueContainer()

		if let intValue {
			try container.encode(intValue)
		} else {
			try container.encodeNil()
		}
	}
}
