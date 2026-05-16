//
//  Transmitter.swift
//  SatScheduler
//
//  Created by bi119aTe5hXk on 2026/05/16.
//

import Foundation

struct Transmitter: Codable, Identifiable, Hashable {
	let uuid: String
	let description: String?
	let alive: Bool?
	let type: String?

	let uplink_low: Int?
	let uplink_high: Int?
	let uplink_drift: Int?

	let downlink_low: Int?
	let downlink_high: Int?
	let downlink_drift: Int?

	let mode: String?
	let mode_id: Int?
	let uplink_mode: String?
	let invert: Bool?
	let baud: Double?

	let sat_id: String?
	let norad_cat_id: Int?
	let norad_follow_id: Int?

	let status: String?
	let updated: String?
	let citation: String?
	let service: String?
	let iaru_coordination: String?
	let iaru_coordination_url: String?
	let itu_notification: ITUNotification?
	let frequency_violation: Bool?
	let unconfirmed: Bool?

	let total_count: Int?
	let unknown_count: Int?
	let future_count: Int?
	let good_count: Int?
	let bad_count: Int?
	let unknown_rate: Int?
	let future_rate: Int?
	let success_rate: Int?
	let bad_rate: Int?

	var id: String {
		uuid
	}

	var isActive: Bool {
		status == "active" && alive == true
	}

	var displayName: String {
		let desc = description?.trimmingCharacters(in: .whitespacesAndNewlines)
		let modeText = mode?.trimmingCharacters(in: .whitespacesAndNewlines)

		if let desc, !desc.isEmpty, let modeText, !modeText.isEmpty {
			return "\(desc) / \(modeText)"
		}

		if let desc, !desc.isEmpty {
			return desc
		}

		if let modeText, !modeText.isEmpty {
			return modeText
		}

		return uuid
	}

	var downlinkText: String {
		guard let downlink_low else {
			return "-"
		}

		let lowMHz = Double(downlink_low) / 1_000_000.0

		if let downlink_high {
			let highMHz = Double(downlink_high) / 1_000_000.0
			return String(format: "%.3f-%.3f MHz", lowMHz, highMHz)
		}

		return String(format: "%.3f MHz", lowMHz)
	}

	var baudText: String {
		guard let baud else {
			return "-"
		}

		if baud.rounded() == baud {
			return String(format: "%.0f", baud)
		}

		return String(baud)
	}
	
	var downlinkFrequencyText: String {

		guard let downlink_low else {
			return "-"
		}
		if let downlink_high, downlink_high != downlink_low {
			return "\(formatFrequencyMHz(downlink_low))-\(formatFrequencyMHz(downlink_high)) MHz"
		}
		return "\(formatFrequencyMHz(downlink_low)) MHz"

	}

	var defaultCenterFrequencyHz: Int? {

		guard let downlink_low else {
			return nil
		}
		if let downlink_high, downlink_high != downlink_low {
			return (downlink_low + downlink_high) / 2
		}
		return downlink_low

	}

	func formatFrequencyMHz(_ frequencyHz: Int) -> String {

		let mhz = Double(frequencyHz) / 1_000_000.0
		return String(format: "%.6f", mhz)
			.replacingOccurrences(of: "0+$", with: "", options: .regularExpression)
			.replacingOccurrences(of: "\\.$", with: "", options: .regularExpression)

	}
	
	var requiresManualCenterFrequency: Bool {

		guard let downlink_low, let downlink_high else {
			return false
		}
		return downlink_high != downlink_low

	}
}

struct ITUNotification: Codable, Hashable {
	let urls: [String]?
}
