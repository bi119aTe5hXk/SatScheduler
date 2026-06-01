//
//  AutoSchedulePreviewView.swift
//  SatScheduler
//
//  Created by bi119aTe5hXk on 2026/05/19.
//

import SwiftUI

struct AutoSchedulePreviewView: View {
	let targets: [WatchTarget]
	let start: Date
	let end: Date

	@Environment(\.dismiss) private var dismiss
	@StateObject private var viewModel = AutoSchedulePreviewViewModel()
	@State private var schedulingTask: Task<Void, Never>?

	var body: some View {
		NavigationStack {
			contentView
				.navigationTitle("Auto Schedule Preview")
#if os(iOS)
				.navigationBarTitleDisplayMode(.inline)
#endif
				.toolbar {
					ToolbarItem(placement: .cancellationAction) {
						Button("Close") {
							cancelSchedulingIfNeeded()
							dismiss()
						}
					}
#if os(iOS)
					ToolbarItem(placement: .primaryAction) {
						EditButton()
							.disabled(viewModel.isPlanning || viewModel.isScheduling || viewModel.plan?.selectedCandidates.isEmpty != false)
					}
#endif
					ToolbarItem(placement: .primaryAction) {
						Button {
							Task {
								await viewModel.makePlan(
									targets: targets,
									start: start,
									end: end
								)
							}
						} label: {
							if viewModel.isPlanning {
								ProgressView()
									.controlSize(.small)
							} else {
								Label("Recalculate", systemImage: "arrow.clockwise")
							}
						}
						.disabled(viewModel.isPlanning || viewModel.isScheduling)
					}
				}
				.safeAreaInset(edge: .bottom) {
					bottomActionBar
				}
				.alert("Auto Schedule", isPresented: Binding(
					get: { viewModel.message != nil },
					set: { if !$0 { viewModel.clearMessage() } }
				)) {
					Button("OK", role: .cancel) {}
				} message: {
					Text(viewModel.message ?? "")
				}
				.task {
					if viewModel.plan == nil {
						await viewModel.makePlan(
							targets: targets,
							start: start,
							end: end
						)
					}
				}
				.onDisappear {
					cancelSchedulingIfNeeded()
				}
		}
	}

	@ViewBuilder
	private var contentView: some View {
		if viewModel.isPlanning && viewModel.plan == nil {
			VStack(spacing: 12) {
				ProgressView()
				Text(viewModel.planningStatusText.isEmpty ? "Calculating schedule plan..." : viewModel.planningStatusText)
					.font(.headline)
					.multilineTextAlignment(.center)
					.padding(.horizontal)
			}
			.frame(maxWidth: .infinity, maxHeight: .infinity)
		} else {
			List {
				Section("Priority") {
					Picker("Priority mode", selection: $viewModel.priorityMode) {
						ForEach(AutoSchedulePriorityMode.allCases) { mode in
							Text(mode.title).tag(mode)
						}
					}

					Text(viewModel.priorityMode.description)
						.font(.caption)
						.foregroundStyle(.secondary)
				}
				.onChange(of: viewModel.priorityMode) { _, newMode in
					viewModel.resortCurrentPlan(priorityMode: newMode)
				}

				if let plan = viewModel.plan {
					Section("Summary") {
						LabeledContent("Target count", value: "\(targets.filter { $0.enabled }.count)")
						LabeledContent("Candidate passes", value: "\(plan.candidateCount)")
						LabeledContent("Will schedule", value: "\(plan.selectedCount)")
						LabeledContent("Skipped", value: "\(plan.skippedCount)")
						LabeledContent("Range", value: "\(formatDateTime(plan.start)) – \(formatDateTime(plan.end))")
					}

					Section("Station Timeline") {
						AutoScheduleStationTimelineOverview(
							plan: plan,
							timelineObservations: viewModel.timelineObservations,
							createdObservations: viewModel.createdObservations,
							executionResults: viewModel.executionResults
						)
					}

					if !viewModel.createdObservations.isEmpty {
						Section("Created") {
							Text("Created \(viewModel.createdObservations.count) observation(s).")
								.foregroundStyle(.green)
						}
					}

					Section("Selected Passes") {
						if plan.selectedCandidates.isEmpty {
							ContentUnavailableView(
								"No Passes Selected",
								systemImage: "calendar.badge.exclamationmark",
								description: Text("No pass matches the current filters and priority mode.")
							)
						} else {
							ForEach(plan.selectedCandidates) { candidate in
								if viewModel.isScheduling {
									AutoScheduleCandidateRow(
										candidate: candidate,
										executionResult: viewModel.executionResult(for: candidate)
									)
									.moveDisabled(true)
									.disabled(true)
								} else {
									AutoScheduleCandidateRow(
										candidate: candidate,
										executionResult: viewModel.executionResult(for: candidate)
									)
									.swipeActions(edge: .trailing, allowsFullSwipe: true) {
										Button(role: .destructive) {
											viewModel.removeSelectedCandidate(candidate)
										} label: {
											Label("Remove", systemImage: "trash")
										}
									}
									.moveDisabled(false)
								}
							}
							.onMove { source, destination in
								guard !viewModel.isScheduling else {
									return
								}

								viewModel.moveSelectedCandidates(fromOffsets: source, toOffset: destination)
							}
						}
					}

					if !plan.skippedCandidates.isEmpty {
						Section("Skipped Conflicts") {
							ForEach(plan.skippedCandidates) { skipped in
								AutoScheduleSkippedCandidateRow(skipped: skipped)
							}
						}
					}
				} else {
					Section {
						ContentUnavailableView(
							"No Plan",
							systemImage: "calendar",
							description: Text("Click Recalculate to generate an auto schedule plan.")
						)
					}
				}
			}
		}
	}

	private var bottomActionBar: some View {
		VStack(spacing: 8) {
			if viewModel.isScheduling {
				ProgressView(value: Double(viewModel.scheduleProgress.created), total: Double(max(viewModel.scheduleProgress.total, 1))) {
					Text("Scheduling \(viewModel.scheduleProgress.created) / \(viewModel.scheduleProgress.total)")
				}
			}

			if viewModel.hasCompletedScheduleSuccessfully {
				Text("All selected passes have already been submitted.")
					.font(.caption)
					.foregroundStyle(.secondary)
			} else if viewModel.hasRetryableFailedPasses {
				Text("Retry will submit failed passes only.")
					.font(.caption)
					.foregroundStyle(.secondary)
			}

			Button {
				schedulingTask?.cancel()
				schedulingTask = Task {
					await viewModel.scheduleSelectedPasses()
				}
			} label: {
				if viewModel.isScheduling {
					ProgressView()
						.controlSize(.small)
					Text(viewModel.isRetryingFailedPasses ? "Retrying..." : "Scheduling...")
				} else {
					Label(viewModel.scheduleButtonTitle, systemImage: viewModel.scheduleButtonSystemImage)
				}
			}
			.buttonStyle(.borderedProminent)
			.disabled(viewModel.isPlanning || viewModel.isScheduling || !viewModel.canStartScheduling)
		}
		.padding()
		.background(viewModel.isScheduling ? AnyShapeStyle(.bar) : AnyShapeStyle(.clear))
	}

	private func cancelSchedulingIfNeeded() {
		guard viewModel.isScheduling else {
			return
		}

		viewModel.cancelScheduling()
		schedulingTask?.cancel()
		schedulingTask = nil
	}

	private func formatDateTime(_ date: Date) -> String {
		let formatter = DateFormatter()
		formatter.dateStyle = .short
		formatter.timeStyle = .short
		return formatter.string(from: date)
	}
}
