//
//  TLEEntry.swift
//  SatScheduler
//
//  Created by bi119aTe5hXk on 2026/05/16.
//
import Foundation

struct TLEEntry: Codable, Identifiable, Hashable {
	let tle0: String?
	let tle1: String
	let tle2: String
	let tle_source: String?
	let sat_id: String
	let norad_cat_id: Int?
	let updated: String?

	var id: String {
		[
			sat_id,
			tle_source ?? "unknown",
			updated ?? "unknown"
		]
		.joined(separator: "-")
	}

	var name: String {
		let trimmed = tle0?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
		return trimmed.isEmpty ? sat_id : trimmed
	}

	var updatedDate: Date? {
		guard let updated else {
			return nil
		}

		return TLEEntry.updatedDateFormatter.date(from: updated)
	}

	private static let updatedDateFormatter: DateFormatter = {
		let formatter = DateFormatter()
		formatter.locale = Locale(identifier: "en_US_POSIX")
		formatter.timeZone = TimeZone(secondsFromGMT: 0)
		formatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ss.SSSSSSZ"
		return formatter
	}()
}
