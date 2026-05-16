//
//  ObservationInfoTabView.swift
//  SatScheduler
//
//  Created by bi119aTe5hXk on 2026/05/17.
//
import SwiftUI

struct ObservationInfoTabView: View {
	let observation: Observation
#if os(iOS)
	@Environment(\.horizontalSizeClass) private var horizontalSizeClass
#endif

	var body: some View {
		GeometryReader { geometry in
			ScrollView {
				if shouldUseHorizontalLayout(width: geometry.size.width) {
					HStack(alignment: .top, spacing: 20) {
						infoColumn
							.frame(maxWidth: .infinity, alignment: .topLeading)

						polarPlotCard
							.frame(width: min(340, max(260, geometry.size.width * 0.36)))
					}
					.padding(20)
				} else {
					VStack(alignment: .leading, spacing: 16) {
						infoColumn
						polarPlotCard
					}
					.padding(16)
				}
			}
		}
	}

	private var infoColumn: some View {
		VStack(alignment: .leading, spacing: 16) {
			infoCard("Observation") {
				infoRow("ID", String(observation.id))
				infoRow("Status", observation.statusDisplayText)
				infoRow("Start", formatObservationDate(observation.start))
				infoRow("End", formatObservationDate(observation.end))

				if let riseAzimuth = observation.rise_azimuth {
					infoRow("Rise Azimuth", formatDegrees(riseAzimuth))
				}
				if let setAzimuth = observation.set_azimuth {
					infoRow("Set Azimuth", formatDegrees(setAzimuth))
				}
				if let maxAltitude = observation.max_altitude {
					infoRow("Max Altitude", formatDegrees(maxAltitude))
				}
			}

			infoCard("Satellite") {
				infoRow("Name", satelliteName)

				if let noradID = observation.norad_cat_id {
					infoRow("NORAD", String(noradID))
				}
				if let satID = observation.sat_id, !satID.isEmpty {
					infoRow("Sat ID", satID)
				}
			}

			infoCard("Station / Transmitter") {
				infoRow("Ground Station", observation.stationDisplayName)
				infoRow("Transmitter", observation.transmitterDisplayName)

				if !observation.frequencyText.isEmpty {
					infoRow("Frequency", observation.frequencyText)
				}
			}
		}
	}

	@ViewBuilder
	private var polarPlotCard: some View {
		if observation.rise_azimuth != nil ||
			observation.set_azimuth != nil ||
			observation.max_altitude != nil {
			infoCard("Polar Plot") {
				ObservationPolarPlotView(
					riseAzimuth: observation.rise_azimuth,
					setAzimuth: observation.set_azimuth,
					maxAltitude: observation.max_altitude
				)
				.frame(maxWidth: .infinity)
				.frame(height: 220)
			}
		}
	}

	private func shouldUseHorizontalLayout(width: CGFloat) -> Bool {
#if os(iOS)
		return horizontalSizeClass == .regular && width >= 760
#else
		return width >= 760
#endif
	}

	private func infoCard<Content: View>(
		_ title: String,
		@ViewBuilder content: () -> Content
	) -> some View {
		VStack(alignment: .leading, spacing: 12) {
			Text(title)
				.font(.headline)

			VStack(alignment: .leading, spacing: 8) {
				content()
			}
		}
		.padding(14)
		.frame(maxWidth: .infinity, alignment: .leading)
		.background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
	}

	private func infoRow(_ title: String, _ value: String) -> some View {
		HStack(alignment: .firstTextBaseline, spacing: 12) {
			Text(title)
				.font(.subheadline)
				.foregroundStyle(.secondary)
				.frame(width: 130, alignment: .leading)

			Text(value)
				.font(.subheadline)
				.textSelection(.enabled)
				.frame(maxWidth: .infinity, alignment: .leading)
		}
	}

	private var satelliteName: String {
		if let satelliteName = observation.satellite_name, !satelliteName.isEmpty {
			return satelliteName
		}

		if let tle0 = observation.tle0, !tle0.isEmpty {
			return tle0
		}

		if let satID = observation.sat_id, !satID.isEmpty {
			return satID
		}

		return observation.norad_cat_id.map { "NORAD \($0)" } ?? "-"
	}

	private func formatDegrees(_ value: Double) -> String {
		String(format: "%.1f°", value)
	}

	private func formatObservationDate(_ string: String?) -> String {
		guard let string, !string.isEmpty else {
			return "-"
		}
		return string
	}
}
