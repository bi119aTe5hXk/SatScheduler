//
//  AutoScheduleCandidateRow.swift
//  SatScheduler
//
//  Created by bi119aTe5hXk on 2026/05/19.
//

import SwiftUI

struct AutoScheduleCandidateRow: View {
	let candidate: AutoScheduleCandidate
	let executionResult: AutoScheduleExecutionResult?

	init(
		candidate: AutoScheduleCandidate,
		executionResult: AutoScheduleExecutionResult? = nil
	) {
		self.candidate = candidate
		self.executionResult = executionResult
	}

	var body: some View {
		VStack(alignment: .leading, spacing: 6) {
			HStack(alignment: .top, spacing: 8) {
				Text(candidate.satelliteName)
					.font(.headline)

				Spacer(minLength: 8)

				if let executionResult {
					statusBadge(for: executionResult.status)
				}
			}

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

	@ViewBuilder
	private func statusBadge(for status: AutoScheduleExecutionStatus) -> some View {
		HStack(spacing: 4) {
			Image(systemName: statusIconName(for: status))
			Text(statusText(for: status))
		}
		.font(.caption2.weight(.semibold))
		.foregroundStyle(statusColor(for: status))
		.padding(.horizontal, 8)
		.padding(.vertical, 4)
		.background(statusColor(for: status).opacity(0.12), in: Capsule())
	}

	private func statusText(for status: AutoScheduleExecutionStatus) -> String {
		switch status {
		case .pending:
			return "Pending"
		case .running:
			return "Scheduling..."
		case .success(let createdCount):
			return "Created \(createdCount)"
		case .failure(let message):
			return "Failed: \(message)"
		}
	}

	private func statusIconName(for status: AutoScheduleExecutionStatus) -> String {
		switch status {
		case .pending:
			return "circle"
		case .running:
			return "clock.arrow.circlepath"
		case .success:
			return "checkmark.circle.fill"
		case .failure:
			return "xmark.circle.fill"
		}
	}

	private func statusColor(for status: AutoScheduleExecutionStatus) -> Color {
		switch status {
		case .pending:
			return .secondary
		case .running:
			return .orange
		case .success:
			return .green
		case .failure:
			return .red
		}
	}
}
