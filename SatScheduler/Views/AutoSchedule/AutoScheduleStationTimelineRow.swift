//
//  AutoScheduleStationTimelineRow.swift
//  SatScheduler
//
//  Created by bi119aTe5hXk on 2026/05/19.
//

import SwiftUI

struct AutoScheduleStationTimelineRow: View {
	let stationID: Int
	let plan: AutoSchedulePlan

	private var stationName: String {
		plan.selectedCandidates.first { $0.request.groundStationID == stationID }?.stationName
			?? "Station \(stationID)"
	}

	private var existingObservations: [Observation] {
		plan.existingObservations.filter { observation in
			observation.ground_station == stationID
		}
	}

	private var plannedCandidates: [AutoScheduleCandidate] {
		plan.selectedCandidates.filter { candidate in
			candidate.request.groundStationID == stationID
		}
	}

	var body: some View {
		VStack(alignment: .leading, spacing: 6) {
			Text(stationName)
				.font(.caption)
				.foregroundStyle(.secondary)

			AutoScheduleTimelineBar(
				start: plan.start,
				end: plan.end,
				existingObservations: existingObservations,
				plannedCandidates: plannedCandidates
			)
			.frame(height: 28)
		}
	}
}





