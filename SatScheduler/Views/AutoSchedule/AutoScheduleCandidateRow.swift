//
//  AutoScheduleCandidateRow.swift
//  SatScheduler
//
//  Created by bi119aTe5hXk on 2026/05/19.
//

import SwiftUI

struct AutoScheduleCandidateRow: View {
	let candidate: AutoScheduleCandidate

	var body: some View {
		VStack(alignment: .leading, spacing: 6) {
			Text(candidate.satelliteName)
				.font(.headline)

			Text(candidate.stationName)
				.font(.subheadline)
				.foregroundStyle(.secondary)

			HStack {
				Label(timeRangeText, systemImage: "clock")
				Spacer()
				Label(String(format: "Peak %.1f°", candidate.peakElevation), systemImage: "angle")
			}
			.font(.caption)
			.foregroundStyle(.secondary)

			HStack {
				Label(String(format: "Az %.0f°–%.0f°", candidate.passWindow.azimuthStart, candidate.passWindow.azimuthEnd), systemImage: "location.north.line")
				Spacer()
				Text(formatDuration(candidate.duration))
			}
			.font(.caption)
			.foregroundStyle(.secondary)
		}
		.padding(.vertical, 4)
	}

	private var timeRangeText: String {
		"\(formatTime(candidate.request.start)) – \(formatTime(candidate.request.end))"
	}

	private func formatTime(_ date: Date) -> String {
		let formatter = DateFormatter()
		formatter.timeStyle = .short
		formatter.dateStyle = .short
		return formatter.string(from: date)
	}

	private func formatDuration(_ duration: TimeInterval) -> String {
		let minutes = Int(duration / 60)
		return "\(minutes) min"
	}
}
