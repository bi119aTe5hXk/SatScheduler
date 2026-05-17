//
//  StationScheduleListView.swift
//  SatScheduler
//
//  Created by bi119aTe5hXk on 2026/05/16.
//
import SwiftUI

struct StationScheduleListView: View {
	let stationSchedules: [StationScheduleTimeline]

	var body: some View {
		ScrollView {
			VStack(alignment: .leading, spacing: 14) {
				ForEach(stationSchedules) { stationSchedule in
					VStack(alignment: .leading, spacing: 8) {
//						Text(stationSchedule.displayName)
//							.font(.headline)

						ForEach(stationSchedule.observations) { observation in
							HStack(alignment: .top, spacing: 12) {
								VStack(alignment: .leading, spacing: 4) {
									Text(satelliteDisplayName(for: observation))
										.font(.subheadline)

									Text("\(formatDateTime(observation.start)) - \(formatTime(observation.end)) UTC \(readableDurationText(from: observation.start, to: observation.end))")
										.font(.caption)
										.foregroundStyle(.secondary)

									if !observation.transmitterDescription.isEmpty {
										Text(observation.transmitterDescription)
											.font(.caption2)
											.foregroundStyle(.secondary)
									}
								}

								Spacer()

								Text(relativeTimeFromNowText(for: observation.start))
									.font(.caption)
									.foregroundStyle(relativeTimeFromNowColor(for: observation.start))
							}
							.padding(10)
							.background(.secondary.opacity(0.08))
							.clipShape(RoundedRectangle(cornerRadius: 8))
						}
					}
				}
			}
		}
	}

	private func satelliteDisplayName(for observation: StationScheduleObservation) -> String {
		let satelliteName = observation.satelliteName.trimmingCharacters(in: .whitespacesAndNewlines)
		let tle0 = observation.tle0?
//			.replacingOccurrences(of: "^0\\s+", with: "", options: .regularExpression)
			.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

		let displayName: String
		if !satelliteName.isEmpty {
			print(satelliteName)
			displayName = satelliteName
		} else if !tle0.isEmpty {
			displayName = tle0
		} else {
			displayName = "Observation \(observation.id)"
		}

		if displayName.contains("(") && displayName.contains(")") {
			return displayName
		}

		return "\(displayName) (\(observation.id))"
	}

	private func formatTime(_ date: Date) -> String {
		let formatter = DateFormatter()
		formatter.locale = Locale(identifier: "en_US_POSIX")
		formatter.timeZone = TimeZone(secondsFromGMT: 0)
		formatter.dateFormat = "HH:mm"
		return formatter.string(from: date)
	}

	private func formatDateTime(_ date: Date) -> String {
		let formatter = DateFormatter()
		formatter.locale = Locale(identifier: "en_US_POSIX")
		formatter.timeZone = TimeZone(secondsFromGMT: 0)
		formatter.dateFormat = "yyyy-MM-dd HH:mm"
		return formatter.string(from: date)
	}
	
	private func readableDurationText(from start: Date, to end: Date) -> String {
		let seconds = max(0, end.timeIntervalSince(start))
		let minutes = Int((seconds / 60).rounded())

		if minutes < 60 {
			return "\(max(1, minutes))min"
		}

		let hours = minutes / 60
		let remainingMinutes = minutes % 60

		if remainingMinutes == 0 {
			return "\(hours)hr"
		}

		return "\(hours)hr \(remainingMinutes)min"
	}

	private func relativeTimeFromNowText(for date: Date, now: Date = Date()) -> String {
		let seconds = date.timeIntervalSince(now)
		let absoluteSeconds = abs(seconds)

		if absoluteSeconds < 60 {
			return seconds >= 0 ? "now" : "started"
		}

		let minutes = Int((absoluteSeconds / 60).rounded())
		let value: String

		if minutes < 60 {
			value = "\(minutes)min"
		} else {
			let hours = minutes / 60
			let remainingMinutes = minutes % 60
			value = remainingMinutes == 0 ? "\(hours)hr" : "\(hours)hr \(remainingMinutes)min"
		}

		return seconds >= 0 ? "\(value) from now" : "\(value) ago"
	}

	private func relativeTimeFromNowColor(for date: Date, now: Date = Date()) -> Color {
		date >= now ? .secondary : .orange
	}
}
