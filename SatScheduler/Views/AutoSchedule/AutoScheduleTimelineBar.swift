//
//  AutoScheduleTimelineBar.swift
//  SatScheduler
//
//  Created by bi119aTe5hXk on 2026/05/19.
//
import SwiftUI

struct AutoScheduleTimelineBar: View {
	let start: Date
	let end: Date
	let existingObservations: [Observation]
	let plannedCandidates: [AutoScheduleCandidate]

	private var totalDuration: TimeInterval {
		max(end.timeIntervalSince(start), 1)
	}

	var body: some View {
		GeometryReader { proxy in
			ZStack(alignment: .leading) {
				RoundedRectangle(cornerRadius: 4)
					.fill(Color.secondary.opacity(0.15))

				ForEach(Array(existingObservations.enumerated()), id: \.offset) { _, observation in
					if let observationStart = observation.startDate,
					   let observationEnd = observation.endDate {
						AutoScheduleTimelineBlock(
							start: observationStart,
							end: observationEnd,
							rangeStart: start,
							rangeEnd: end,
							color: .blue,
							width: proxy.size.width
						)
					}
				}

				ForEach(plannedCandidates) { candidate in
					AutoScheduleTimelineBlock(
						start: candidate.request.start,
						end: candidate.request.end,
						rangeStart: start,
						rangeEnd: end,
						color: .yellow,
						width: proxy.size.width
					)
				}

				let now = Date()
				if now >= start && now <= end {
					Rectangle()
						.fill(Color.green)
						.frame(width: 2)
						.offset(x: xOffset(for: now, width: proxy.size.width))
				}
			}
		}
	}

	private func xOffset(for date: Date, width: CGFloat) -> CGFloat {
		let rawRatio = date.timeIntervalSince(start) / totalDuration
		let ratio = min(max(rawRatio, 0), 1)
		return CGFloat(ratio) * width
	}
}

