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
						if let target = viewModel.makeWatchTarget() {
							onSave(target)
						}
					}
					.disabled(!viewModel.canSave)
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
}
