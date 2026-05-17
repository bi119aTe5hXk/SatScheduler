//
//  StationScheduleTimelineView.swift
//  SatScheduler
//
//  Created by bi119aTe5hXk on 2026/05/16.
//
import SwiftUI
import Combine

struct StationScheduleTimelineView: View {
	let start: Date
	let end: Date
	let stationSchedules: [StationScheduleTimeline]
	let refreshingStationID: Int?
	let onRefreshStation: (Int) async -> Void

	@State private var selectedStationSchedule: StationScheduleTimeline?
	@State private var currentDate: Date
	@State private var timelineStartDate: Date

	private let labelWidth: CGFloat = 220
	private let rowHeight: CGFloat = 34
	private let currentTimeLineWidth: CGFloat = 2
	private let currentTimeTimer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()
	private let timelineDuration: TimeInterval = 3 * 24 * 60 * 60

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

		let now = Date()
		_currentDate = State(initialValue: now)
		_timelineStartDate = State(initialValue: now)
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

									if isCurrentTimeVisible {
										Rectangle()
											.fill(.green)
											.frame(width: currentTimeLineWidth, height: rowHeight + 6)
											.offset(x: currentTimeXOffset(width: timelineWidth))
											.help(currentTimeTooltip)
											.zIndex(10)
									}

									ForEach(visibleObservations(for: stationSchedule)) { observation in
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
		.onAppear {
			currentDate = Date()
		}
		.onReceive(currentTimeTimer) { date in
			currentDate = date
			if date > timelineEndDate {
				timelineStartDate = date
			}
		}
	}

	private var timelineHeader: some View {
		HStack {
			Text("Station")
				.font(.caption)
				.foregroundStyle(.secondary)
				.frame(width: labelWidth - 12, alignment: .leading)

			HStack {
				Text(formatDateTime(timelineStartDate))
				Spacer()
				Text(formatDateTime(timelineEndDate))
			}
			.font(.caption)
			.foregroundStyle(.secondary)
		}
	}

	private var timelineEndDate: Date {
		timelineStartDate.addingTimeInterval(timelineDuration)
	}

	private var isCurrentTimeVisible: Bool {
		currentDate >= timelineStartDate && currentDate <= timelineEndDate
	}

	private var currentTimeTooltip: String {
		"Current time: \(formatDateTime(currentDate)) UTC"
	}

	private func currentTimeXOffset(width: CGFloat) -> CGFloat {
		xOffset(for: currentDate, width: width) - currentTimeLineWidth / 2
	}

	private func xOffset(for date: Date, width: CGFloat) -> CGFloat {
		let total = timelineEndDate.timeIntervalSince(timelineStartDate)
		guard total > 0 else {
			return 0
		}

		let offset = date.timeIntervalSince(timelineStartDate)
		return max(0, min(width, CGFloat(offset / total) * width))
	}

	private func barWidth(for observation: StationScheduleObservation, timelineWidth: CGFloat) -> CGFloat {
		let total = timelineEndDate.timeIntervalSince(timelineStartDate)
		guard total > 0 else {
			return 0
		}

		let clippedStart = observation.start > timelineStartDate ? observation.start : timelineStartDate
		let clippedEnd = observation.end < timelineEndDate ? observation.end : timelineEndDate
		let duration = max(0, clippedEnd.timeIntervalSince(clippedStart))
		return CGFloat(duration / total) * timelineWidth
	}
	private func visibleObservations(for stationSchedule: StationScheduleTimeline) -> [StationScheduleObservation] {
		stationSchedule.observations.filter { observation in
			observation.start < timelineEndDate && observation.end > timelineStartDate
		}
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
