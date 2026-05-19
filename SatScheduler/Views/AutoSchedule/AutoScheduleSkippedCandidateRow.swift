//
//  AutoScheduleSkippedCandidateRow.swift
//  SatScheduler
//
//  Created by bi119aTe5hXk on 2026/05/19.
//
import SwiftUI
struct AutoScheduleSkippedCandidateRow: View {
	let skipped: AutoScheduleSkippedCandidate

	var body: some View {
		VStack(alignment: .leading, spacing: 6) {
			Text(skipped.candidate.satelliteName)
				.font(.headline)

			Text(skipped.reason.title)
				.font(.caption)
				.foregroundStyle(.red)

			Text("\(skipped.candidate.stationName) / \(formatTime(skipped.candidate.request.start)) – \(formatTime(skipped.candidate.request.end))")
				.font(.caption)
				.foregroundStyle(.secondary)

			if let conflictingCandidate = skipped.conflictingCandidate {
				Text("Conflicts with: \(conflictingCandidate.satelliteName)")
					.font(.caption)
					.foregroundStyle(.secondary)
			}
		}
		.padding(.vertical, 4)
	}

	private func formatTime(_ date: Date) -> String {
		let formatter = DateFormatter()
		formatter.timeStyle = .short
		formatter.dateStyle = .short
		return formatter.string(from: date)
	}
}

