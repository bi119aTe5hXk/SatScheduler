//
//  ViewUtils.swift
//  SatScheduler
//
//  Created by bi119aTe5hXk on 2026/05/16.
//
import Foundation
import SwiftUI

private let timeDisplayModeStorageKey = "SatScheduler.timeDisplayMode"

var timeDisplayMode: String {
	UserDefaults.standard.string(forKey: timeDisplayModeStorageKey) ?? TimeDisplayMode.utc.rawValue
}

func durationText(for pass: PassWindow) -> String {
	let minutes = Int(pass.end.timeIntervalSince(pass.start) / 60)
	return "\(minutes)m"
}

var selectedTimeDisplayMode: TimeDisplayMode {
	TimeDisplayMode(rawValue: timeDisplayMode) ?? .utc
}

func formatDateTime(_ date: Date) -> String {
	let formatter = DateFormatter()
	formatter.locale = Locale(identifier: "en_US_POSIX")
	formatter.timeZone = selectedTimeDisplayMode.timeZone
	formatter.dateFormat = "yyyy-MM-dd HH:mm"
	return formatter.string(from: date)
}

func formatTime(_ date: Date) -> String {
	let formatter = DateFormatter()
	formatter.locale = Locale(identifier: "en_US_POSIX")
	formatter.timeZone = selectedTimeDisplayMode.timeZone
	formatter.dateFormat = "HH:mm"
	return formatter.string(from: date)
}


enum ObservationAssetURLBuilder {
	static func waterfallURL(for observation: Observation) -> URL? {
		guard let waterfall = observation.waterfall, !waterfall.isEmpty else {
			return nil
		}
		return URL(string: waterfall)

	}
	static func audioURL(for observation: Observation) -> URL? {
		guard let payload = observation.payload, !payload.isEmpty else {
			return nil
		}
		return URL(string: payload)
	}
}
