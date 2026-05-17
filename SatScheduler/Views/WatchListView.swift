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
			.alert("Auto Schedule", isPresented: Binding(
				get: { autoScheduleMessage != nil },
				set: { if !$0 { autoScheduleMessage = nil } }
			)) {
				Button("OK", role: .cancel) {}
			} message: {
				Text(autoScheduleMessage ?? "")
			}
			.sheet(item: $predictionPreviewTarget) { target in
				WatchTargetPredictionPreviewView(target: target)
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

	private func runAutoSchedule() async {
		guard authManager.isLoggedIn else {
			authManager.requireLoginPrompt()
			return
		}

		isAutoScheduling = true
		defer { isAutoScheduling = false }

		do {
			let createdCount = try await viewModel.autoScheduleAllTargets()
			autoScheduleMessage = "Created \(createdCount) observation(s)."
		} catch {
			autoScheduleMessage = error.localizedDescription
		}
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
