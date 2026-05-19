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

			if target.requiresStationDaylight {
				Label("Require station daylight", systemImage: "sun.max")
					.font(.caption)
					.foregroundStyle(.orange)
			}

			if let peakElevationRangeText {
				Label(peakElevationRangeText, systemImage: "angle")
					.font(.caption)
					.foregroundStyle(.secondary)
			}

			if let azimuthRangeText {
				Label(azimuthRangeText, systemImage: "location.north.line")
					.font(.caption)
					.foregroundStyle(.secondary)
			}
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

	private var peakElevationRangeText: String? {
		let minText = target.minPeakElevation.map { String(format: "%.0f°", $0) }
		let maxText = target.maxPeakElevation.map { String(format: "%.0f°", $0) }

		switch (minText, maxText) {
		case let (min?, max?):
			return "Peak elevation: \(min) – \(max)"
		case let (min?, nil):
			return "Peak elevation: ≥ \(min)"
		case let (nil, max?):
			return "Peak elevation: ≤ \(max)"
		case (nil, nil):
			return nil
		}
	}

	private var azimuthRangeText: String? {
		guard let minAzimuth = target.minAzimuth,
			  let maxAzimuth = target.maxAzimuth else {
			return nil
		}

		let minText = String(format: "%.0f°", minAzimuth)
		let maxText = String(format: "%.0f°", maxAzimuth)
		return "Azimuth: \(minText) – \(maxText)"
	}
}
