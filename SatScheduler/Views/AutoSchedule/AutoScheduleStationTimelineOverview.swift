//
//  AutoScheduleStationTimelineOverview.swift
//  SatScheduler
//
//  Created by bi119aTe5hXk on 2026/05/19.
//

import SwiftUI

struct AutoScheduleStationTimelineOverview: View {
	let plan: AutoSchedulePlan
	let timelineObservations: [Observation]
	let createdObservations: [Observation]
	let executionResults: [AutoScheduleExecutionResult]

	private var visibleTimelineObservations: [Observation] {
		timelineObservations.isEmpty ? plan.existingObservations : timelineObservations
	}

	private var stationIDs: [Int] {
		let existingStationIDs = visibleTimelineObservations.compactMap { $0.ground_station }
		let selectedStationIDs = plan.selectedCandidates.map { $0.request.groundStationID }
		let executionStationIDs = executionResults.map { $0.candidate.request.groundStationID }
		return Array(Set(existingStationIDs + selectedStationIDs + executionStationIDs)).sorted()
	}

	var body: some View {
		if stationIDs.isEmpty {
			ContentUnavailableView(
				"No Station Timeline",
				systemImage: "calendar.badge.exclamationmark",
				description: Text("No existing or planned observations are available for this time range.")
			)
		} else {
			VStack(alignment: .leading, spacing: 12) {
				AutoScheduleTimelineLegend()

				ForEach(stationIDs, id: \.self) { stationID in
					AutoScheduleStationTimelineRow(
						stationID: stationID,
						plan: plan,
						timelineObservations: visibleTimelineObservations,
						createdObservations: createdObservations,
						executionResults: executionResults
					)
				}
			}
			.padding(.vertical, 4)
		}
	}
}
