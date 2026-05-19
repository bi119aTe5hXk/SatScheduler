//
//  AutoScheduleTimelineBlock.swift
//  SatScheduler
//
//  Created by bi119aTe5hXk on 2026/05/19.
//

import SwiftUI

struct AutoScheduleTimelineBlock: View {
	let start: Date
	let end: Date
	let rangeStart: Date
	let rangeEnd: Date
	let color: Color
	let width: CGFloat

	private var totalDuration: TimeInterval {
		max(rangeEnd.timeIntervalSince(rangeStart), 1)
	}

	var body: some View {
		let clippedStart = max(start, rangeStart)
		let clippedEnd = min(end, rangeEnd)
		let startRatio = clippedStart.timeIntervalSince(rangeStart) / totalDuration
		let endRatio = clippedEnd.timeIntervalSince(rangeStart) / totalDuration
		let blockWidth = max(CGFloat(endRatio - startRatio) * width, 3)
		let xOffset = CGFloat(startRatio) * width

		RoundedRectangle(cornerRadius: 3)
			.fill(color.opacity(0.85))
			.frame(width: blockWidth)
			.padding(.vertical, 5)
			.offset(x: xOffset)
	}
}

