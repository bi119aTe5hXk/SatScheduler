//
//  PredictionTimelineView.swift
//  SatScheduler
//
//  Created by bi119aTe5hXk on 2026/05/16.
//
import SwiftUI
import Combine

struct PredictionTimelineView: View {
	let start: Date
	let end: Date
	let stationTimelines: [StationPassTimeline]

	private let rowHeight: CGFloat = 34
	private let labelWidth: CGFloat = 180
	private let currentTimeLineWidth: CGFloat = 2
	private let currentTimeTimer = Timer.publish(every: 30, on: .main, in: .common).autoconnect()
	
	@AppStorage("SatScheduler.timeDisplayMode") private var timeDisplayMode = TimeDisplayMode.utc.rawValue
	@State private var currentDate = Date()

	var body: some View {
		VStack(alignment: .leading, spacing: 10) {
			timelineHeader

			GeometryReader { geometry in
				let timelineWidth = max(geometry.size.width - labelWidth, 1)

				VStack(alignment: .leading, spacing: 10) {
					ForEach(stationTimelines) { stationTimeline in
						HStack(spacing: 12) {
							Text(stationTimeline.displayName)
								.font(.caption)
								.lineLimit(1)
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

								ForEach(stationTimeline.passes) { pass in
									let x = xOffset(for: pass.start, width: timelineWidth)
									let width = barWidth(for: pass, timelineWidth: timelineWidth)

									RoundedRectangle(cornerRadius: 5)
										.fill(.blue.opacity(0.75))
										.frame(width: max(width, 3), height: 22)
										.offset(x: x)
										.help(passTooltip(pass))
								}
							}
							.frame(width: timelineWidth, height: rowHeight)
						}
					}
				}
			}
			.frame(height: CGFloat(stationTimelines.count) * (rowHeight + 10))
		}
		.onReceive(currentTimeTimer) { date in
			currentDate = date
		}
	}

	private var timelineHeader: some View {
		HStack {
			Text("Station")
				.font(.caption)
				.foregroundStyle(.secondary)
				.frame(width: labelWidth - 12, alignment: .leading)

			HStack {
				Text(start.formatted(date: .omitted, time: .shortened))
				Spacer()
				Text(end.formatted(date: .abbreviated, time: .shortened))
			}
			.font(.caption)
			.foregroundStyle(.secondary)
		}
	}

	private var isCurrentTimeVisible: Bool {
		currentDate >= start && currentDate <= end
	}

	private var currentTimeTooltip: String {
		"Current time: \(formatDateTime(currentDate)) \(selectedTimeDisplayMode.label)"
	}

	private func currentTimeXOffset(width: CGFloat) -> CGFloat {
		xOffset(for: currentDate, width: width) - currentTimeLineWidth / 2
	}

	private func xOffset(for date: Date, width: CGFloat) -> CGFloat {
		let total = end.timeIntervalSince(start)
		guard total > 0 else {
			return 0
		}

		let offset = date.timeIntervalSince(start)
		return CGFloat(offset / total) * width
	}

	private func barWidth(for pass: PassWindow, timelineWidth: CGFloat) -> CGFloat {
		let total = end.timeIntervalSince(start)
		guard total > 0 else {
			return 0
		}

		let duration = pass.end.timeIntervalSince(pass.start)
		return CGFloat(duration / total) * timelineWidth
	}

	private func passTooltip(_ pass: PassWindow) -> String {

		let elevation = String(format: "%.1f", pass.maxElevation)
		return """
		\(formatDateTime(pass.start)) - \(formatDateTime(pass.end)) \(selectedTimeDisplayMode.label)
		Max elevation: \(elevation)°
		"""

	}
}
