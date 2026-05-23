//
//  ObservationsView.swift
//  SatScheduler
//
//  Created by bi119aTe5hXk on 2026/05/16.
//

import SwiftUI

struct ObservationsView: View {
	@StateObject private var viewModel = ObservationsViewModel()
	@StateObject private var observerIDStore = ObserverIDStore.shared
	@State private var observerIDDraft = ""
	@State private var isShowingObserverIDEditor = false

	var body: some View {
		NavigationStack {
			contentView
				.navigationTitle(observationsTitle)
				.toolbar {
					ToolbarItem(placement: .primaryAction) {
						Button {
							Task {
								await refreshObservations()
							}
						} label: {
							if viewModel.isLoading {
								ProgressView()
									.controlSize(.small)
							} else {
								Label("Refresh", systemImage: "arrow.clockwise")
							}
						}
						.disabled(viewModel.isLoading)
					}

//					ToolbarItem(placement: .secondaryAction) {
//						Button("Observer ID") {
//							observerIDDraft = observerIDStore.observerIDText
//							isShowingObserverIDEditor = true
//						}
//					}
				}
				.sheet(isPresented: $isShowingObserverIDEditor) {
					NavigationStack {
						Form {
							Section("SatNOGS Observer") {
								TextField("Observer ID", text: $observerIDDraft)
#if os(iOS)
									.keyboardType(.numberPad)
#endif
								Text("Used for /api/observations/?status=unknown&observer=<id>.")
									.font(.caption)
									.foregroundStyle(.secondary)
							}
						}
						.navigationTitle("Observer ID")
						.toolbar {
							ToolbarItem(placement: .confirmationAction) {
								Button("Done") {
									observerIDStore.saveObserverIDText(observerIDDraft)
									isShowingObserverIDEditor = false
									Task {
										await refreshObservations()
									}
								}
							}
						}
					}
					.frame(minWidth: 420, minHeight: 180)
				}
		}
	}

	@ViewBuilder
	private var contentView: some View {
		if observerID == nil {
			VStack(spacing: 12) {
				Image(systemName: "person.crop.circle.badge.questionmark")
					.font(.largeTitle)
					.foregroundStyle(.secondary)
				Text("Observer ID is not set.")
					.font(.headline)
				Text("Set your SatNOGS observer ID to load observations that need rating.")
					.foregroundStyle(.secondary)
				Button("Set Observer ID") {
					observerIDDraft = observerIDStore.observerIDText
					isShowingObserverIDEditor = true
				}
			}
			.frame(maxWidth: .infinity, maxHeight: .infinity)
		} else if viewModel.isLoading && viewModel.observations.isEmpty {
			ProgressView("Loading observations...")
				.frame(maxWidth: .infinity, maxHeight: .infinity)
		} else if let errorMessage = viewModel.errorMessage, viewModel.observations.isEmpty {
			VStack(spacing: 12) {
				Text(errorMessage)
					.foregroundStyle(.red)
				Button("Retry") {
					Task {
						await refreshObservations()
					}
				}
			}
			.frame(maxWidth: .infinity, maxHeight: .infinity)
		} else if viewModel.observations.isEmpty {
			VStack(spacing: 12) {
				Image(systemName: "checkmark.circle")
					.font(.largeTitle)
					.foregroundStyle(.secondary)
				Text("No unrated observations.")
					.font(.headline)
				Text("There are no observations with unknown status for this observer.")
					.foregroundStyle(.secondary)
			}
			.frame(maxWidth: .infinity, maxHeight: .infinity)
		} else {
			List {
				ForEach(viewModel.observations) { observation in
					NavigationLink {
						ObservationDetailView(observation: observation)
					} label: {
						ObservationRowView(observation: observation)
					}
					.task {
						await viewModel.loadMoreUnknownObservationsIfNeeded(
							currentObservation: observation,
							observerID: observerID
						)
					}
				}

				if viewModel.isLoadingNextPage {
					HStack {
						Spacer()
						ProgressView()
						Spacer()
					}
				}
			}
			.refreshable {
				await refreshObservations()
			}
		}
	}

	private var observerID: Int? {
		observerIDStore.observerID
	}

	@MainActor
	private func refreshObservations() async {
		guard let observerID else {
			return
		}

		await viewModel.loadUnknownObservations(observerID: observerID)
	}
	
	private var observationsTitle: String {
		return "Observations"
//		if viewModel.isLoading {
//			return "Observations"
//		}
//
//		return "Observations (\(viewModel.observations.count))"
	}
}
