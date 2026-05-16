//
//  ObservationPolarPlotView.swift
//  SatScheduler
//
//  Created by bi119aTe5hXk on 2026/05/17.
//

import SwiftUI

struct ObservationPolarPlotView: View {
	let riseAzimuth: Double?
	let setAzimuth: Double?
	let maxAltitude: Double?

	private let padding: CGFloat = 24

	var body: some View {
		GeometryReader { geometry in
			let size = min(geometry.size.width, geometry.size.height)
			let center = CGPoint(x: geometry.size.width / 2, y: geometry.size.height / 2)
			let radius = max(0, size / 2 - padding)

			ZStack {
				polarGrid(center: center, radius: radius)
				passPath(center: center, radius: radius)
				azimuthMarkers(center: center, radius: radius)
			}
			.frame(maxWidth: .infinity, maxHeight: .infinity)
		}
	}

	@ViewBuilder
	private func polarGrid(center: CGPoint, radius: CGFloat) -> some View {
		ForEach([0.25, 0.5, 0.75, 1.0], id: \.self) { scale in
			Circle()
				.stroke(.secondary.opacity(scale == 1.0 ? 0.45 : 0.2), lineWidth: scale == 1.0 ? 1.2 : 0.8)
				.frame(width: radius * 2 * scale, height: radius * 2 * scale)
				.position(center)
		}

		Path { path in
			path.move(to: CGPoint(x: center.x, y: center.y - radius))
			path.addLine(to: CGPoint(x: center.x, y: center.y + radius))
			path.move(to: CGPoint(x: center.x - radius, y: center.y))
			path.addLine(to: CGPoint(x: center.x + radius, y: center.y))
		}
		.stroke(.secondary.opacity(0.22), lineWidth: 0.8)

		Text("N")
			.font(.caption.bold())
			.position(x: center.x, y: center.y - radius - 12)
		Text("E")
			.font(.caption.bold())
			.position(x: center.x + radius + 12, y: center.y)
		Text("S")
			.font(.caption.bold())
			.position(x: center.x, y: center.y + radius + 12)
		Text("W")
			.font(.caption.bold())
			.position(x: center.x - radius - 12, y: center.y)
	}

	@ViewBuilder
	private func passPath(center: CGPoint, radius: CGFloat) -> some View {
		if let riseAzimuth, let setAzimuth, let maxAltitude {
			Path { path in
				let points = sampledPassPoints(
					riseAzimuth: riseAzimuth,
					setAzimuth: setAzimuth,
					maxAltitude: maxAltitude,
					center: center,
					radius: radius
				)

				guard let first = points.first else {
					return
				}

				path.move(to: first)
				for point in points.dropFirst() {
					path.addLine(to: point)
				}
			}
			.stroke(.primary, style: StrokeStyle(lineWidth: 2.5, lineCap: .round, lineJoin: .round))
		}
	}

	@ViewBuilder
	private func azimuthMarkers(center: CGPoint, radius: CGFloat) -> some View {
		if let riseAzimuth {
			let point = pointFor(azimuth: riseAzimuth, altitude: 0, center: center, radius: radius)
			marker(title: "Rise", value: riseAzimuth, point: point)
		}

		if let setAzimuth {
			let point = pointFor(azimuth: setAzimuth, altitude: 0, center: center, radius: radius)
			marker(title: "Set", value: setAzimuth, point: point)
		}

		if let riseAzimuth, let setAzimuth, let maxAltitude {
			let azimuth = interpolatedAzimuth(start: riseAzimuth, end: setAzimuth, progress: 0.5)
			let point = pointFor(azimuth: azimuth, altitude: maxAltitude, center: center, radius: radius)
			marker(title: "Max", value: maxAltitude, point: point)
		}
	}

	private func marker(title: String, value: Double, point: CGPoint) -> some View {
		VStack(spacing: 2) {
			Circle()
				.fill(.primary)
				.frame(width: 7, height: 7)
			Text("\(title) \(String(format: "%.0f°", value))")
				.font(.caption2)
				.foregroundStyle(.secondary)
		}
		.position(point)
	}

	private func sampledPassPoints(
		riseAzimuth: Double,
		setAzimuth: Double,
		maxAltitude: Double,
		center: CGPoint,
		radius: CGFloat
	) -> [CGPoint] {
		let risePoint = pointFor(azimuth: riseAzimuth, altitude: 0, center: center, radius: radius)
		let setPoint = pointFor(azimuth: setAzimuth, altitude: 0, center: center, radius: radius)
		let maxAzimuth = interpolatedAzimuth(start: riseAzimuth, end: setAzimuth, progress: 0.5)
		let maxPoint = pointFor(azimuth: maxAzimuth, altitude: maxAltitude, center: center, radius: radius)

		let controlPoint = CGPoint(
			x: 2 * maxPoint.x - (risePoint.x + setPoint.x) / 2,
			y: 2 * maxPoint.y - (risePoint.y + setPoint.y) / 2
		)

		return (0...72).map { index in
			let progress = CGFloat(index) / 72.0
			return quadraticBezierPoint(
				start: risePoint,
				control: controlPoint,
				end: setPoint,
				progress: progress
			)
		}
	}

	private func quadraticBezierPoint(
		start: CGPoint,
		control: CGPoint,
		end: CGPoint,
		progress: CGFloat
	) -> CGPoint {
		let t = max(0, min(1, progress))
		let oneMinusT = 1 - t

		return CGPoint(
			x: oneMinusT * oneMinusT * start.x + 2 * oneMinusT * t * control.x + t * t * end.x,
			y: oneMinusT * oneMinusT * start.y + 2 * oneMinusT * t * control.y + t * t * end.y
		)
	}

	private func pointFor(
		azimuth: Double,
		altitude: Double,
		center: CGPoint,
		radius: CGFloat
	) -> CGPoint {
		let normalizedAltitude = max(0, min(90, altitude)) / 90.0
		let distance = radius * CGFloat(1.0 - normalizedAltitude)
		let radians = azimuth * Double.pi / 180.0
		return CGPoint(
			x: center.x + distance * CGFloat(sin(radians)),
			y: center.y - distance * CGFloat(cos(radians))
		)
	}

	private func interpolatedAzimuth(start: Double, end: Double, progress: Double) -> Double {
		var delta = end - start
		if delta > 180 {
			delta -= 360
		} else if delta < -180 {
			delta += 360
		}

		let value = start + delta * progress
		return value < 0 ? value + 360 : value.truncatingRemainder(dividingBy: 360)
	}
}
