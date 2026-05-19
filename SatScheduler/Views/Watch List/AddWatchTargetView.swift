//
//  AddWatchTargetView.swift
//  SatScheduler
//
//  Created by bi119aTe5hXk on 2026/05/16.
//

import SwiftUI

struct AddWatchTargetView: View {
	@Environment(\.dismiss) private var dismiss

	let onSave: (WatchTarget) -> Void

	@StateObject var viewModel = AddWatchTargetViewModel()
	@State private var requireStationDaylight = false
	@State private var minPeakElevationText = ""
	@State private var maxPeakElevationText = ""
	@State private var minAzimuthText = ""
	@State private var maxAzimuthText = ""

	var body: some View {
		NavigationStack {
			List {
				Section("Satellite") {
					TextField("Search satellites", text: $viewModel.satelliteSearchText)
						.textFieldStyle(.roundedBorder)

					if let selectedSatelliteID = viewModel.selectedSatelliteID,
					   let selectedSatellite = viewModel.satellites.first(where: { $0.id == selectedSatelliteID }) {
						HStack {
							Text("Selected: \(viewModel.displayName(for: selectedSatellite))")
								.foregroundStyle(.secondary)

							Spacer()

							Button("Clear") {
								viewModel.selectedSatelliteID = nil
								viewModel.selectedTransmitterID = nil
								viewModel.centerFrequencyMHzText = ""
								viewModel.transmitters = []
							}
						}
					}

					if viewModel.isLoadingSatellites {
						ProgressView()
					} else {
						if viewModel.filteredSatellites.isEmpty && !viewModel.satelliteSearchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
							Text("No satellites found.")
								.foregroundStyle(.secondary)
								.frame(maxWidth: .infinity, alignment: .center)
								.padding(.vertical, 24)
						} else {
							ForEach(Array(viewModel.filteredSatellites.prefix(100))) { satellite in
								Button {
									viewModel.selectedSatelliteID = satellite.id
									viewModel.satelliteSearchText = viewModel.displayName(for: satellite)

									Task {
										await viewModel.loadTransmitters(for: satellite.id)
									}
								} label: {
									HStack {
										VStack(alignment: .leading, spacing: 4) {
											Text(viewModel.displayName(for: satellite))

											if let norad = satellite.norad_cat_id {
												Text("NORAD: \(norad) / \(satellite.countries ?? "-")")
													.font(.caption)
													.foregroundStyle(.secondary)
											}
										}

										Spacer()

										if viewModel.selectedSatelliteID == satellite.id {
											Image(systemName: "checkmark")
												.foregroundStyle(.blue)
										}
									}
								}
								.buttonStyle(.plain)
							}
						}
					}
				}

				Section("Transmitter") {
					if viewModel.isLoadingTransmitters {
						ProgressView()
					} else if viewModel.transmitters.isEmpty {
						Text(viewModel.selectedSatelliteID == nil ? "Select a satellite first." : "No transmitters found.")
							.foregroundStyle(.secondary)
					} else {
						Menu {
							ForEach(viewModel.transmitters) { transmitter in
								Button {
									viewModel.selectTransmitter(transmitter)
								} label: {
									Text(viewModel.displayName(for: transmitter))
								}
							}
						} label: {
							HStack {
								Text(selectedTransmitterText)
									.foregroundStyle(viewModel.selectedTransmitter == nil ? .secondary : .primary)

								Spacer()

								Image(systemName: "chevron.down")
									.foregroundStyle(.secondary)
							}
						}

						if let transmitter = viewModel.selectedTransmitter {
							VStack(alignment: .leading, spacing: 8) {
								Text("Downlink: \(transmitter.downlinkFrequencyText)")
									.font(.caption)
									.foregroundStyle(.secondary)

								if transmitter.requiresManualCenterFrequency {
									TextField("Center frequency MHz", text: $viewModel.centerFrequencyMHzText)
										.textFieldStyle(.roundedBorder)

									Text("This transmitter has a frequency range. Input the center frequency used for scheduling.")
										.font(.caption)
										.foregroundStyle(.secondary)
								} else if let centerFrequency = viewModel.centerFrequencyHz {
									Text("Center frequency: \(transmitter.formatFrequencyMHz(centerFrequency)) MHz")
										.font(.caption)
										.foregroundStyle(.secondary)
								}
							}
						}
					}
				}

				Section("Ground Stations") {
					TextField("Search ground stations", text: $viewModel.stationSearchText)
						.textFieldStyle(.roundedBorder)

					if viewModel.isLoadingStations {
						ProgressView()
					} else if viewModel.filteredStations.isEmpty && !viewModel.stationSearchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
						Text("No ground stations found.")
							.foregroundStyle(.secondary)
							.frame(maxWidth: .infinity, alignment: .center)
							.padding(.vertical, 24)
					} else {
						ForEach(viewModel.filteredStations) { station in
							Button {
								viewModel.toggleStation(station)
							} label: {
								HStack {
									VStack(alignment: .leading, spacing: 4) {
										Text(station.displayName)
											.font(.headline)

										Text("ID: \(station.id) / \(station.status ?? "-")")
											.font(.caption)
											.foregroundStyle(.secondary)

										Text("\(station.antennaText) / Alt: \(station.altitudeText)")
											.font(.caption)
											.foregroundStyle(.secondary)

										if let successRate = station.successRateValue {
											Text("Success: \(successRate)% / Future: \(station.future_observations ?? 0)")
												.font(.caption2)
												.foregroundStyle(.secondary)
										}
									}

									Spacer()

									if viewModel.selectedStationIDs.contains(station.id) {
										Image(systemName: "checkmark.circle.fill")
									}
								}
							}
							.buttonStyle(.plain)
						}
					}
				}

				Section("Scheduling Options") {
					Toggle("Require station daylight", isOn: $requireStationDaylight)

					Text("Only schedule observations when the selected ground station is in daylight. Use this for satellites that transmit only when solar powered.")
						.font(.caption)
						.foregroundStyle(.secondary)

					VStack(alignment: .leading, spacing: 8) {
						Text("Peak elevation range")
							.font(.subheadline)

						HStack {
							TextField("Min °", text: $minPeakElevationText)
								.textFieldStyle(.roundedBorder)
#if os(iOS)
								.keyboardType(.decimalPad)
#endif

							Text("–")
								.foregroundStyle(.secondary)

							TextField("Max °", text: $maxPeakElevationText)
								.textFieldStyle(.roundedBorder)
#if os(iOS)
								.keyboardType(.decimalPad)
#endif
						}

						Text("Optional. If set, passes whose peak elevation is outside this range will be ignored. Leave blank to disable the limit.")
							.font(.caption)
							.foregroundStyle(.secondary)

						if let peakElevationValidationMessage {
							Text(peakElevationValidationMessage)
								.font(.caption)
								.foregroundStyle(.red)
						}
					}

					VStack(alignment: .leading, spacing: 8) {
						Text("Azimuth range")
							.font(.subheadline)

						HStack {
							TextField("Min °", text: $minAzimuthText)
								.textFieldStyle(.roundedBorder)
#if os(iOS)
								.keyboardType(.decimalPad)
#endif

							Text("–")
								.foregroundStyle(.secondary)

							TextField("Max °", text: $maxAzimuthText)
								.textFieldStyle(.roundedBorder)
#if os(iOS)
								.keyboardType(.decimalPad)
#endif
						}

						Text("Optional. Passes are kept if any point of the trajectory crosses this azimuth range. Use 300–60 to cover a range crossing north.")
							.font(.caption)
							.foregroundStyle(.secondary)

						if let azimuthValidationMessage {
							Text(azimuthValidationMessage)
								.font(.caption)
								.foregroundStyle(.red)
						}
					}
				}

				if let errorMessage = viewModel.errorMessage {
					Section {
						Text(errorMessage)
							.foregroundStyle(.red)
					}
				}
			}
			.navigationTitle("Add Watch Target")
			.toolbar {
				ToolbarItem(placement: .cancellationAction) {
					Button("Cancel") {
						dismiss()
					}
				}

				ToolbarItem(placement: .confirmationAction) {
					Button("Add") {
						if var target = viewModel.makeWatchTarget() {
							target.requireStationDaylight = requireStationDaylight ? true : nil
							target.minPeakElevation = parsedMinPeakElevation
							target.maxPeakElevation = parsedMaxPeakElevation
							target.minAzimuth = parsedMinAzimuth
							target.maxAzimuth = parsedMaxAzimuth
							onSave(target)
						}
					}
					.disabled(!viewModel.canSave || !isPeakElevationRangeValid || !isAzimuthRangeValid)
				}
			}
			.task {
				await viewModel.loadInitialData()
			}
		}
//		.frame(minWidth: 620, minHeight: 640)
	}

	private var selectedTransmitterText: String {
		guard let transmitter = viewModel.selectedTransmitter else {
			return "Select Transmitter"
		}

		return viewModel.displayName(for: transmitter)
	}

	private var parsedMinPeakElevation: Double? {
		parsePeakElevation(minPeakElevationText)
	}

	private var parsedMaxPeakElevation: Double? {
		parsePeakElevation(maxPeakElevationText)
	}

	private var isPeakElevationRangeValid: Bool {
		peakElevationValidationMessage == nil
	}

	private var peakElevationValidationMessage: String? {
		let minText = minPeakElevationText.trimmingCharacters(in: .whitespacesAndNewlines)
		let maxText = maxPeakElevationText.trimmingCharacters(in: .whitespacesAndNewlines)

		if !minText.isEmpty && parsedMinPeakElevation == nil {
			return "Minimum peak elevation must be between 0 and 90 degrees."
		}

		if !maxText.isEmpty && parsedMaxPeakElevation == nil {
			return "Maximum peak elevation must be between 0 and 90 degrees."
		}

		if let min = parsedMinPeakElevation,
		   let max = parsedMaxPeakElevation,
		   min > max {
			return "Minimum peak elevation must not be greater than maximum peak elevation."
		}

		return nil
	}

	private func parsePeakElevation(_ text: String) -> Double? {
		let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
		guard !trimmed.isEmpty else {
			return nil
		}

		guard let value = Double(trimmed), value >= 0, value <= 90 else {
			return nil
		}

		return value
	}

	private var parsedMinAzimuth: Double? {
		parseAzimuth(minAzimuthText)
	}

	private var parsedMaxAzimuth: Double? {
		parseAzimuth(maxAzimuthText)
	}

	private var isAzimuthRangeValid: Bool {
		azimuthValidationMessage == nil
	}

	private var azimuthValidationMessage: String? {
		let minText = minAzimuthText.trimmingCharacters(in: .whitespacesAndNewlines)
		let maxText = maxAzimuthText.trimmingCharacters(in: .whitespacesAndNewlines)

		if minText.isEmpty && maxText.isEmpty {
			return nil
		}

		if minText.isEmpty || maxText.isEmpty {
			return "Input both minimum and maximum azimuth, or leave both blank."
		}

		if parsedMinAzimuth == nil {
			return "Minimum azimuth must be between 0 and 360 degrees."
		}

		if parsedMaxAzimuth == nil {
			return "Maximum azimuth must be between 0 and 360 degrees."
		}

		return nil
	}

	private func parseAzimuth(_ text: String) -> Double? {
		let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
		guard !trimmed.isEmpty else {
			return nil
		}

		guard let value = Double(trimmed), value >= 0, value <= 360 else {
			return nil
		}

		return value
	}
}
