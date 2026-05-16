//
//  StationPassListView.swift
//  SatScheduler
//
//  Created by bi119aTe5hXk on 2026/05/16.
//
import SwiftUI

struct StationPassListView: View {
	let stationTimeline: StationPassTimeline
	
	@StateObject private var viewModel = WatchTargetPredictionPreviewViewModel()
	
	var body: some View {
		VStack(alignment: .leading, spacing: 8) {
			Text(stationTimeline.displayName)
				.font(.headline)

			ForEach(stationTimeline.passes) { pass in
				HStack {
					VStack(alignment: .leading, spacing: 4) {
						Text("\(formatDateTime(pass.start)) - \(formatTime(pass.end)) \(selectedTimeDisplayMode.label)")
							.font(.subheadline)

						Text("Max elevation: \(String(format: "%.1f", pass.maxElevation))° / Az: \(String(format: "%.0f", pass.azimuthStart))° → \(String(format: "%.0f", pass.azimuthEnd))°")
							.font(.caption)
							.foregroundStyle(.secondary)
					}

					Spacer()

					Text(durationText(for: pass))
						.font(.caption)
						.foregroundStyle(.secondary)
				}
				.padding(10)
				.background(.secondary.opacity(0.08))
				.clipShape(RoundedRectangle(cornerRadius: 8))
			}
		}
	}

}
