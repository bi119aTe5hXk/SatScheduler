//
//  WatchTargetRow.swift
//  SatScheduler
//
//  Created by bi119aTe5hXk on 2026/05/16.
//
import SwiftUI

struct WatchTargetRow: View {
	let target: WatchTarget

	var body: some View {
		VStack(alignment: .leading, spacing: 6) {
			Text(target.name)
				.font(.headline)

			if let satelliteName = target.satelliteName, !satelliteName.isEmpty {
				Text(satelliteName)
					.font(.subheadline)
					.foregroundStyle(.secondary)
			}

			if let transmitterDescription = target.transmitterDescription, !transmitterDescription.isEmpty {
				Text(transmitterDescription)
					.font(.caption)
					.foregroundStyle(.secondary)
			}

			Text("Stations: \(stationDisplayText)")
				.font(.caption)
				.foregroundStyle(.secondary)
		}
		.padding(.vertical, 4)
	}

	private var stationDisplayText: String {
		target.stationIDs
			.map { stationID in
				if let stationName = target.stationNames?[stationID], !stationName.isEmpty {
					return "\(stationName)(\(stationID))"
				}

				return "Unknown station \(stationID)"
			}
			.joined(separator: ", ")
	}
}


