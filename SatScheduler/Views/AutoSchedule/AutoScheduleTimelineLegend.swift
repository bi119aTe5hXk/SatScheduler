//
//  AutoScheduleTimelineLegend.swift
//  SatScheduler
//
//  Created by bi119aTe5hXk on 2026/05/19.
//

import SwiftUI

struct AutoScheduleTimelineLegend: View {
	var body: some View {
		HStack(spacing: 12) {
			legendItem(color: .blue, title: "Existing")
			legendItem(color: .yellow, title: "Planned")
			legendItem(color: .green, title: "Now")
		}
		.font(.caption)
		.foregroundStyle(.secondary)
	}

	private func legendItem(color: Color, title: String) -> some View {
		HStack(spacing: 4) {
			RoundedRectangle(cornerRadius: 2)
				.fill(color)
				.frame(width: 12, height: 8)
			Text(title)
		}
	}
}

