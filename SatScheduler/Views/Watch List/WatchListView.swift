//
//  WatchListView.swift
//  SatScheduler
//
//  Created by bi119aTe5hXk on 2026/05/16.
//
import SwiftUI

struct WatchListView: View {
	@StateObject private var viewModel = WatchListViewModel()
	@EnvironmentObject private var authManager: AuthManager
#if os(iOS)
	@Environment(\.editMode) private var editMode
#else
	@State private var isEditingWatchTargets = false
#endif
	@State private var isShowingAddTargetSheet = false
	@State private var isAutoScheduling = false
	@State private var autoScheduleMessage: String?
	@State private var autoScheduleResult: AutoScheduleBatchResult?
	@State private var autoScheduleProgress: [AutoScheduleTargetResult] = []
	@State private var isShowingAutoScheduleProgress = false
	@State private var isAutoScheduleCancelled = false
	@State private var predictionPreviewTarget: WatchTarget?

	var body: some View {
		NavigationStack {
			Group {
				if viewModel.watchTargets.isEmpty {
					ContentUnavailableView(
						"No Watch Targets",
						systemImage: "dot.radiowaves.left.and.right",
						description: Text("Add a satellite, transmitter and ground station to start scheduling observations.")
					)
				} else {
					List {
						ForEach(viewModel.watchTargets) { target in
						#if os(macOS)
							HStack(spacing: 8) {
								WatchTargetRow(target: target)
									.contentShape(Rectangle())
									.onTapGesture(count: 1) {
										guard !isEditingWatchTargets else {
											return
										}
										predictionPreviewTarget = target
									}

								if isEditingWatchTargets {
									VStack(spacing: 4) {
										Button {
											viewModel.moveTargetUp(target)
										} label: {
											Image(systemName: "chevron.up")
										}
										.buttonStyle(.borderless)
										.disabled(viewModel.isFirstTarget(target))

										Button {
											viewModel.moveTargetDown(target)
										} label: {
											Image(systemName: "chevron.down")
										}
										.buttonStyle(.borderless)
										.disabled(viewModel.isLastTarget(target))
									}
								}
							}
						#else
							WatchTargetRow(target: target)
								.contentShape(Rectangle())
								.onTapGesture(count: 1) {
									predictionPreviewTarget = target
								}
						#endif
						}
						.onDelete(perform: viewModel.deleteTargets)
						.onMove(perform: viewModel.moveTargets)
					}
					.refreshable {
						viewModel.loadWatchTargets()
					}
				}
			}
			.navigationTitle("Watch List")
			.toolbar {
				ToolbarItem(placement: .cancellationAction) {

#if os(iOS)

					EditButton()
						.disabled(viewModel.watchTargets.isEmpty)

#else

					Button(isEditingWatchTargets ? "Done" : "Edit") {
						toggleWatchTargetEditing()
					}
					.disabled(viewModel.watchTargets.isEmpty)

#endif
				}
				ToolbarItemGroup(placement: .primaryAction) {
					Button {
						Task {
							await runAutoSchedule()
						}
					} label: {
						if isAutoScheduling {
							ProgressView()
						} else {
							Label("Auto Schedule", systemImage: "arrow.trianglehead.2.clockwise.rotate.90.circle")
						}
					}
					.disabled(viewModel.watchTargets.isEmpty || isAutoScheduling)

					Button {
						isShowingAddTargetSheet = true
					} label: {
						Label("Add", systemImage: "plus")
					}
				}
			}
			.sheet(isPresented: $isShowingAddTargetSheet) {
				AddWatchTargetView { target in
					viewModel.addTarget(target)
					isShowingAddTargetSheet = false
				}
				.adaptiveWatchSheetSizing()
			}
			.sheet(item: $predictionPreviewTarget) { target in
				WatchTargetPredictionPreviewView(target: target)
					.adaptiveWatchSheetSizing()
			}
			.sheet(isPresented: $isShowingAutoScheduleProgress) {
				autoScheduleProgressSheet
					.adaptiveWatchSheetSizing()
			}
			.task {
				viewModel.loadWatchTargets()
			}
		}
	}

#if os(iOS)
	private var isEditingWatchTargets: Bool {
		editMode?.wrappedValue.isEditing == true
	}
#endif

	private func toggleWatchTargetEditing() {
		withAnimation {
#if os(iOS)
			editMode?.wrappedValue = isEditingWatchTargets ? .inactive : .active
#else
			isEditingWatchTargets.toggle()
#endif
		}
	}

	private var autoScheduleProgressSheet: some View {
		NavigationStack {
			List {
				Section {
					HStack {
						Text("Status")
						Spacer()
						if isAutoScheduling {
							if !isAutoScheduleCancelled {
								ProgressView()
									.controlSize(.small)
							}

							Text(isAutoScheduleCancelled ? "Stopping" : "Running")
								.foregroundStyle(isAutoScheduleCancelled ? .red : .green)
						} else if isAutoScheduleCancelled {
							Text("Stopped")
								.foregroundStyle(.red)
						} else {
							Text("Completed")
								.foregroundStyle(.secondary)
						}
					}

					if let autoScheduleResult {
						Text("Created \(autoScheduleResult.createdCount) observation(s).")
						Text("Succeeded targets: \(autoScheduleResult.successResults.count)")
						Text("Failed targets: \(autoScheduleResult.failureResults.count)")
					} else {
						Text("Completed targets: \(autoScheduleProgress.count)")
					}
				}

				Section("Targets") {
					if autoScheduleProgress.isEmpty {
						Text("Waiting to start...")
							.foregroundStyle(.secondary)
					} else {
						ForEach(autoScheduleProgress.reversed()) { result in
							VStack(alignment: .leading, spacing: 4) {
								Text(result.target.satelliteName ?? result.target.satelliteID)
									.font(.headline)
								Text(result.status.displayMessage)
									.font(.caption)
									.foregroundStyle(.secondary)
							}
						}
					}
				}
			}
			.navigationTitle("Auto Schedule")
			.toolbar {
				ToolbarItem(placement: .cancellationAction) {
					Button("Close") {
						isShowingAutoScheduleProgress = false
					}
					.disabled(isAutoScheduling)
				}

				ToolbarItem(placement: .primaryAction) {
					Button("Stop", role: .destructive) {
						isAutoScheduleCancelled = true
					}
					.disabled(!isAutoScheduling || isAutoScheduleCancelled)
				}
			}
		}
	}

	private func runAutoSchedule() async {
		guard authManager.isLoggedIn else {
			authManager.requireLoginPrompt()
			return
		}

		let targets = viewModel.watchTargets
		guard !targets.isEmpty else {
			autoScheduleMessage = "No watch targets to schedule."
			return
		}

		autoScheduleMessage = nil
		autoScheduleResult = nil
		autoScheduleProgress = []
		isAutoScheduleCancelled = false
		isShowingAutoScheduleProgress = true

		isAutoScheduling = true
		defer { isAutoScheduling = false }

		let scheduler = AutoScheduler()
		let startDate = Date()
		let endDate = startDate.addingTimeInterval(2 * 24 * 60 * 60)
		let result = await scheduler.scheduleTargets(
			targets,
			from: startDate,
			to: endDate,
			delayBetweenTargets: 5,
			shouldCancel: {
				isAutoScheduleCancelled
			},
			onProgress: { targetResult in
				autoScheduleProgress.append(targetResult)
			}
		)

		autoScheduleResult = result
		autoScheduleMessage = autoScheduleSummaryMessage(for: result)
	}

	private func autoScheduleSummaryMessage(for result: AutoScheduleBatchResult) -> String {
		var lines: [String] = [
			"Created \(result.createdCount) observation(s).",
			"Succeeded targets: \(result.successResults.count)",
			"Failed targets: \(result.failureResults.count)"
		]

		if !result.failureResults.isEmpty {
			lines.append("")
			lines.append("Failed targets:")
			lines.append(contentsOf: result.failureResults.map { result in
				"- \(result.target.satelliteID): \(result.status.displayMessage)"
			})
		}

		return lines.joined(separator: "\n")
	}
}

private extension View {
	func adaptiveWatchSheetSizing() -> some View {
		modifier(AdaptiveWatchSheetSizingModifier())
	}
}

private struct AdaptiveWatchSheetSizingModifier: ViewModifier {
#if os(iOS)
	@Environment(\.horizontalSizeClass) private var horizontalSizeClass
#endif

	func body(content: Content) -> some View {
#if os(iOS)
		if horizontalSizeClass == .regular {
			content
				.frame(maxWidth: 900, maxHeight: .infinity)
				.frame(maxWidth: .infinity, maxHeight: .infinity)
				.presentationDetents([.large])
				.presentationDragIndicator(.visible)
		} else {
			content
				.frame(maxWidth: .infinity, maxHeight: .infinity)
				.presentationDetents([.large])
				.presentationDragIndicator(.visible)
		}
#else
		content
			.frame(
				minWidth: 720,
				idealWidth: 820,
				maxWidth: 980,
				minHeight: 520,
				idealHeight: 640,
				maxHeight: 760
			)
#endif
	}
}
