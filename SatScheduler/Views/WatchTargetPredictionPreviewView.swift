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
					}
					.frame(maxWidth: .infinity, alignment: .leading)
				}

				GroupBox("Prediction Timeline") {
					contentView
				}

				Spacer()

			}
			.padding(24)
//			.frame(minWidth: 760, minHeight: 560)
//			.navigationTitle("Prediction")
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
							HStack{
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
//				.frame(maxHeight: 220)
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
			let stationIDs = Array(Set(requests.map(\.groundStationID))).sorted()
			let requestStart = requests.map(\.start).min() ?? viewModel.startDate
			let requestEnd = requests.map(\.end).max() ?? viewModel.endDate

			let existingObservations = try await networkService.fetchScheduledObservations(
				start: requestStart,
				end: requestEnd,
				groundStationIDs: stationIDs
			)

			print("Fetched \(existingObservations.count) future observation(s) for stations: \(stationIDs). Request range for local conflict check: \(requestStart) - \(requestEnd)")

			let conflictResult = ObservationScheduleConflictResolver.filterConflicts(
				requests: requests,
				existingObservations: existingObservations,
				conflictBuffer: 30
			)

			guard !conflictResult.allowedRequests.isEmpty else {
				scheduleMessage = "No observations were scheduled. All \(conflictResult.skippedRequests.count) prediction window(s) overlap with existing schedules."
				return
			}

			let observations = try await networkService.createObservations(conflictResult.allowedRequests)
			let skippedCount = conflictResult.skippedRequests.count

			if skippedCount > 0 {
				scheduleMessage = "Scheduled \(observations.count) observation(s). Skipped \(skippedCount) overlapping window(s)."
			} else {
				scheduleMessage = "Scheduled \(observations.count) observation(s)."
			}
		} catch {
			scheduleMessage = "Schedule failed: \(error.localizedDescription)"
		}
	}
}
