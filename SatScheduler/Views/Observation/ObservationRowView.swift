//
//  ObservationRowView.swift
//  SatScheduler
//
//  Created by bi119aTe5hXk on 2026/05/17.
//
import SwiftUI

struct ObservationRowView: View {
	let observation: Observation

	var body: some View {
		VStack(alignment: .leading, spacing: 6) {
			HStack(alignment: .firstTextBaseline) {
				Text(titleText)
					.font(.headline)
				Spacer()
				Text("#\(observation.id)")
					.font(.caption)
					.foregroundStyle(.secondary)
			}

			Text(timeText)
				.font(.caption)
				.foregroundStyle(.secondary)

			HStack(spacing: 12) {
				Text(observation.stationDisplayName)
				Text(observation.transmitterDisplayName)
				Text(observation.statusDisplayText)
			}
			.font(.caption)
			.foregroundStyle(.secondary)

			if !observation.frequencyText.isEmpty {
				Text(observation.frequencyText)
					.font(.caption)
					.foregroundStyle(.secondary)
			}
		}
		.padding(.vertical, 6)
	}

	private var titleText: String {
		if let satelliteName = observation.satellite_name, !satelliteName.isEmpty {
			return satelliteTitle(name: satelliteName)
		}

		if let tle0 = observation.tle0, !tle0.isEmpty {
			return satelliteTitle(name: tle0)
		}

		if let satID = observation.sat_id, !satID.isEmpty {
			return satelliteTitle(name: satID)
		}

		return observation.norad_cat_id.map { "NORAD \($0)" } ?? "Observation \(observation.id)"
	}

	private func satelliteTitle(name: String) -> String {
		let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)

		guard let noradID = observation.norad_cat_id else {
			return trimmedName
		}

		return "\(trimmedName) (\(noradID))"
	}

	private var timeText: String {
		let start = formatObservationDate(observation.start)
		let end = formatObservationDate(observation.end)
		return "\(start) - \(end) UTC"
	}

	private func formatObservationDate(_ string: String?) -> String {
		guard let string,
			  let date = parseObservationDate(string) else {
			return "-"
		}

		let formatter = DateFormatter()
		formatter.locale = Locale(identifier: "en_US_POSIX")
		formatter.timeZone = TimeZone(secondsFromGMT: 0)
		formatter.dateFormat = "yyyy-MM-dd HH:mm"
		return formatter.string(from: date)
	}

	private func parseObservationDate(_ string: String) -> Date? {
		if let date = SatNOGSNetworkService.observationDateFormatter.date(from: string) {
			return date
		}

		if let date = SatNOGSNetworkService.isoFormatter.date(from: string) {
			return date
		}

		let formatter = DateFormatter()
		formatter.locale = Locale(identifier: "en_US_POSIX")
		formatter.timeZone = TimeZone(secondsFromGMT: 0)
		formatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ss.SSSSSSXXXXX"
		return formatter.date(from: string)
	}
}
