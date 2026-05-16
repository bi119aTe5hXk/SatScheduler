//
//  StationScheduleTimelineView.swift
//  SatScheduler
//
//  Created by bi119aTe5hXk on 2026/05/16.
//
import SwiftUI

struct StationScheduleTimelineView: View {
	let start: Date
	let end: Date
	let stationSchedules: [StationScheduleTimeline]
	let refreshingStationID: Int?
	let onRefreshStation: (Int) async -> Void

	@State private var selectedStationSchedule: StationScheduleTimeline?

	private let labelWidth: CGFloat = 220
	private let rowHeight: CGFloat = 34

	init(
		start: Date,
		end: Date,
		stationSchedules: [StationScheduleTimeline],
		refreshingStationID: Int? = nil,
		onRefreshStation: @escaping (Int) async -> Void = { _ in }
	) {
		self.start = start
		self.end = end
		self.stationSchedules = stationSchedules
		self.refreshingStationID = refreshingStationID
		self.onRefreshStation = onRefreshStation
	}

	var body: some View {
		VStack(alignment: .leading, spacing: 10) {
			timelineHeader

			ScrollView {
				GeometryReader { geometry in
					let timelineWidth = max(geometry.size.width - labelWidth, 1)

					VStack(alignment: .leading, spacing: 10) {
						ForEach(stationSchedules) { stationSchedule in
							HStack(spacing: 12) {
								VStack(alignment: .leading, spacing: 4) {
									Text(stationSchedule.displayName)
										.font(.caption)
										.lineLimit(1)

									HStack(spacing: 8) {
										Button {
											Task {
												await onRefreshStation(stationSchedule.stationID)
											}
										} label: {
											if refreshingStationID == stationSchedule.stationID {
												ProgressView()
													.controlSize(.small)
											} else {
												Label("Refresh", systemImage: "arrow.clockwise")
											}
										}
										.buttonStyle(.borderless)
										.disabled(refreshingStationID != nil)

										Button("Show List") {
											selectedStationSchedule = stationSchedule
										}
										.buttonStyle(.borderless)
									}
									.font(.caption2)
								}
								.frame(width: labelWidth - 12, alignment: .leading)

								ZStack(alignment: .leading) {
									RoundedRectangle(cornerRadius: 6)
										.fill(.secondary.opacity(0.12))
										.frame(height: rowHeight)

									ForEach(stationSchedule.observations) { observation in
										RoundedRectangle(cornerRadius: 5)
											.fill(.blue.opacity(0.75))
											.frame(width: max(barWidth(for: observation, timelineWidth: timelineWidth), 3), height: 22)
											.offset(x: xOffset(for: observation.start, width: timelineWidth))
											.help(tooltip(for: observation))
									}
								}
								.frame(width: timelineWidth, height: rowHeight)
							}
						}
					}
				}
				.frame(height: CGFloat(stationSchedules.count) * (rowHeight + 22))
			}
			.frame(minHeight: 180, maxHeight: 420)
		}
		.sheet(item: $selectedStationSchedule) { stationSchedule in
			NavigationStack {
				StationScheduleListView(
					stationSchedules: [stationSchedule]
				)
				.navigationTitle(stationSchedule.displayName)
			}
			.stationScheduleSheetSizing()
		}
	}

	private var timelineHeader: some View {
		HStack {
			Text("Station")
				.font(.caption)
				.foregroundStyle(.secondary)
				.frame(width: labelWidth - 12, alignment: .leading)

			HStack {
				Text(formatDateTime(start))
				Spacer()
				Text(formatDateTime(end))
			}
			.font(.caption)
			.foregroundStyle(.secondary)
		}
	}

	private func xOffset(for date: Date, width: CGFloat) -> CGFloat {
		let total = end.timeIntervalSince(start)
		guard total > 0 else {
			return 0
		}

		let offset = date.timeIntervalSince(start)
		return max(0, min(width, CGFloat(offset / total) * width))
	}

	private func barWidth(for observation: StationScheduleObservation, timelineWidth: CGFloat) -> CGFloat {
		let total = end.timeIntervalSince(start)
		guard total > 0 else {
			return 0
		}

		let clippedStart = observation.start > start ? observation.start : start
		let clippedEnd = observation.end < end ? observation.end : end
		let duration = max(0, clippedEnd.timeIntervalSince(clippedStart))
		return CGFloat(duration / total) * timelineWidth
	}

	private func tooltip(for observation: StationScheduleObservation) -> String {
		"""
		\(observation.satelliteName)
		\(formatDateTime(observation.start)) - \(formatDateTime(observation.end)) UTC
		\(observation.transmitterDescription)
		"""
	}

	private func formatDateTime(_ date: Date) -> String {
		let formatter = DateFormatter()
		formatter.locale = Locale(identifier: "en_US_POSIX")
		formatter.timeZone = TimeZone(secondsFromGMT: 0)
		formatter.dateFormat = "MM-dd HH:mm"
		return formatter.string(from: date)
	}

}

private extension View {
	@ViewBuilder
	func stationScheduleSheetSizing() -> some View {
#if os(iOS)
		self
			.presentationDetents([.large])
			.presentationDragIndicator(.visible)
#else
		self
			.frame(minWidth: 720, idealWidth: 820, maxWidth: 980, minHeight: 520, idealHeight: 640, maxHeight: 760)
#endif
	}
}
