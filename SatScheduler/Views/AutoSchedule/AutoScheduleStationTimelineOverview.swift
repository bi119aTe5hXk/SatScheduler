//
//  AutoScheduleStationTimelineOverview.swift
//  SatScheduler
//
//  Created by bi119aTe5hXk on 2026/05/19.
//

import SwiftUI

struct AutoScheduleStationTimelineOverview: View {
	let plan: AutoSchedulePlan

	private var stationIDs: [Int] {
		let existingStationIDs = plan.existingObservations.compactMap { $0.ground_station }
		let selectedStationIDs = plan.selectedCandidates.map { $0.request.groundStationID }
		return Array(Set(existingStationIDs + selectedStationIDs)).sorted()
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
						plan: plan
					)
				}
			}
			.padding(.vertical, 4)
		}
	}
}
