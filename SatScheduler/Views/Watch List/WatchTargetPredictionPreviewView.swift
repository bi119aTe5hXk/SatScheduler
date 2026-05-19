//
//  WatchTargetPredictionPreviewView.swift
//  SatScheduler
//

import SwiftUI

struct WatchTargetPredictionPreviewView: View {
	@Environment(\.dismiss) private var dismiss

	let target: WatchTarget

	@StateObject private var viewModel = WatchTargetPredictionPreviewViewModel()
	@State private var isScheduling = false
	@State private var scheduleMessage: String?
	
	var body: some View {
		NavigationStack {
			VStack(alignment: .leading, spacing: 20) {
				headerView

				GroupBox("Target") {
					VStack(alignment: .leading, spacing: 8) {
						Text("Satellite: \(target.satelliteName ?? target.name)")
						Text("Transmitter: \(target.transmitterDescription ?? target.transmitterID)")
						Text("Stations: \(stationDisplayText)")

						if target.requiresStationDaylight ||
							target.minPeakElevation != nil ||
							target.maxPeakElevation != nil ||
							target.minAzimuth != nil ||
							target.maxAzimuth != nil {
							Divider()
							VStack(alignment: .leading, spacing: 6) {
								if target.requiresStationDaylight {
									Label("Require station daylight", systemImage: "sun.max")
										.foregroundStyle(.orange)
								}
								if let peakElevationRangeText {
									Label(peakElevationRangeText, systemImage: "angle")
										.foregroundStyle(.secondary)
								}
								if let azimuthRangeText {
									Label(azimuthRangeText, systemImage: "location.north.line")
										.foregroundStyle(.secondary)
								}
							}
							.font(.caption)
						}
					}
					.frame(maxWidth: .infinity, alignment: .leading)
				}

				GroupBox("Prediction Timeline") {
					VStack(alignment: .leading, spacing: 12) {
						predictionFilterSummaryView
						contentView
					}
				}

				Spacer()

			}
			.padding(24)
			.toolbar {
				ToolbarItem(placement: .cancellationAction) {
					Button {
						Task {
							await schedulePredictedObservations()
						}
					} label: {
						if isScheduling {
							ProgressView()
								.controlSize(.small)
							Text("Scheduling...")
						} else {
							HStack {
								Image(systemName: "calendar.badge.plus")
								Text("Schedule Predicted Windows")
							}
						}
					}
					.disabled(isScheduling || viewModel.stationTimelines.allSatisfy { $0.passes.isEmpty })
				}

				ToolbarItem(placement: .confirmationAction) {
					Button("Done") {
						dismiss()
					}
				}
			}
			.alert("Schedule", isPresented: Binding(
				get: { scheduleMessage != nil },
				set: { if !$0 { scheduleMessage = nil } }
			)) {
				Button("OK", role: .cancel) {}
			} message: {
				Text(scheduleMessage ?? "")
			}
			.task {
				await viewModel.loadPrediction(for: target)
			}
		}
	}

	private var headerView: some View {
		VStack(alignment: .leading, spacing: 8) {
			Text("Prediction Timeline")
				.font(.title2)
				.bold()

			Text("Local calculated pass windows for the selected watch target. SatNOGS availability may differ.")
				.foregroundStyle(.secondary)
		}
	}

	@ViewBuilder
	private var predictionFilterSummaryView: some View {
		if let conflictSummary = viewModel.conflictSummary {
			HStack(spacing: 8) {
				Image(systemName: conflictSummary.hiddenCount > 0 ? "exclamationmark.triangle" : "checkmark.circle")
					.foregroundStyle(conflictSummary.hiddenCount > 0 ? .orange : .green)

				Text("Predicted \(conflictSummary.predictedCount), visible \(conflictSummary.visibleCount), hidden \(conflictSummary.hiddenCount).")
					.font(.caption)
					.foregroundStyle(.secondary)
			}
			.padding(.vertical, 6)
			.padding(.horizontal, 10)
			.frame(maxWidth: .infinity, alignment: .leading)
			.background(.thinMaterial, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
		}
	}

	@ViewBuilder
	private var contentView: some View {
		if viewModel.isLoading {
			HStack {
				ProgressView()
				Text("Calculating prediction windows...")
					.foregroundStyle(.secondary)
			}
			.frame(maxWidth: .infinity, alignment: .leading)
			.padding(.vertical, 24)
		} else if let errorMessage = viewModel.errorMessage {
			Text(errorMessage)
				.foregroundStyle(.red)
				.frame(maxWidth: .infinity, alignment: .leading)
				.padding(.vertical, 16)
		} else if viewModel.stationTimelines.isEmpty {
			Text("No prediction windows found.")
				.foregroundStyle(.secondary)
				.frame(maxWidth: .infinity, alignment: .center)
				.padding(.vertical, 32)
		} else {
			VStack(alignment: .leading, spacing: 16) {
				PredictionTimelineView(
					start: viewModel.startDate,
					end: viewModel.endDate,
					stationTimelines: viewModel.stationTimelines
				)

				Divider()

				ScrollView {
					VStack(alignment: .leading, spacing: 12) {
						ForEach(viewModel.stationTimelines) { stationTimeline in
							StationPassListView(stationTimeline: stationTimeline)
						}
					}
				}
			}
			.frame(maxWidth: .infinity, alignment: .leading)
		}
	}

	private var stationDisplayText: String {
		target.stationIDs
			.map { stationID in
				if let stationName = target.stationNames?[stationID], !stationName.isEmpty {
					return "\(stationName) (\(stationID))"
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

	@MainActor
	private func schedulePredictedObservations() async {
		guard !isScheduling else {
			return
		}

		let stationTimelines = viewModel.stationTimelines
		let totalPassCount = stationTimelines.reduce(0) { $0 + $1.passes.count }

		guard totalPassCount > 0 else {
			scheduleMessage = "No prediction windows to schedule."
			return
		}

		isScheduling = true
		defer {
			isScheduling = false
		}

		let requests = stationTimelines.flatMap { stationTimeline in
			stationTimeline.passes.map { passWindow in
				ObservationScheduleRequest(
					groundStationID: stationTimeline.stationID,
					transmitterUUID: target.transmitterID,
					start: passWindow.start,
					end: passWindow.end
				)
			}
		}

		do {
			let networkService = SatNOGSNetworkService()
			let observations = try await networkService.createObservations(requests)
			scheduleMessage = "Scheduled \(observations.count) observation(s)."
		} catch {
			scheduleMessage = "Schedule failed: \(error.localizedDescription)"
		}
	}
}
