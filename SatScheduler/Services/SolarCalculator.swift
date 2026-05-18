//
//  SolarCalculator.swift
//  SatScheduler
//
//  Created by bi119aTe5hXk on 2026/05/18.
//

import Foundation

enum SolarCalculator {

	/// Returns true when the Sun is close enough to the local horizon at the given ground position.
	/// Latitude and longitude are in degrees. Longitude is positive east, negative west.
	/// The default threshold includes civil twilight so observations around sunrise/sunset are not filtered too aggressively.
	static func isDaylight(
		date: Date,
		latitude: Double,
		longitude: Double,
		minimumSolarElevation: Double = -6
	) -> Bool {
		solarElevation(
			date: date,
			latitude: latitude,
			longitude: longitude
		) >= minimumSolarElevation
	}

	/// Approximate solar elevation angle in degrees.
	/// Positive values mean the Sun is above the horizon.
	static func solarElevation(
		date: Date,
		latitude: Double,
		longitude: Double
	) -> Double {
		let julianDay = julianDay(from: date)
		let julianCentury = (julianDay - 2_451_545.0) / 36_525.0

		let geometricMeanLongitude = normalizedDegrees(
			280.46646 + julianCentury * (36_000.76983 + julianCentury * 0.0003032)
		)
		let geometricMeanAnomaly = 357.52911 + julianCentury * (35_999.05029 - 0.0001537 * julianCentury)
		let eccentricity = 0.016708634 - julianCentury * (0.000042037 + 0.0000001267 * julianCentury)

		let equationOfCenter = sin(degreesToRadians(geometricMeanAnomaly)) * (1.914602 - julianCentury * (0.004817 + 0.000014 * julianCentury))
			+ sin(degreesToRadians(2 * geometricMeanAnomaly)) * (0.019993 - 0.000101 * julianCentury)
			+ sin(degreesToRadians(3 * geometricMeanAnomaly)) * 0.000289

		let trueLongitude = geometricMeanLongitude + equationOfCenter
		let omega = 125.04 - 1934.136 * julianCentury
		let apparentLongitude = trueLongitude - 0.00569 - 0.00478 * sin(degreesToRadians(omega))

		let meanObliquity = 23 + (26 + ((21.448 - julianCentury * (46.815 + julianCentury * (0.00059 - julianCentury * 0.001813)))) / 60) / 60
		let obliquityCorrection = meanObliquity + 0.00256 * cos(degreesToRadians(omega))

		let declination = radiansToDegrees(
			asin(sin(degreesToRadians(obliquityCorrection)) * sin(degreesToRadians(apparentLongitude)))
		)

		let varY = tan(degreesToRadians(obliquityCorrection / 2)) * tan(degreesToRadians(obliquityCorrection / 2))
		let equationOfTime = 4 * radiansToDegrees(
			varY * sin(2 * degreesToRadians(geometricMeanLongitude))
				- 2 * eccentricity * sin(degreesToRadians(geometricMeanAnomaly))
				+ 4 * eccentricity * varY * sin(degreesToRadians(geometricMeanAnomaly)) * cos(2 * degreesToRadians(geometricMeanLongitude))
				- 0.5 * varY * varY * sin(4 * degreesToRadians(geometricMeanLongitude))
				- 1.25 * eccentricity * eccentricity * sin(2 * degreesToRadians(geometricMeanAnomaly))
		)

		let minutesUTC = utcMinutesSinceStartOfDay(for: date)
		let trueSolarTime = normalizedMinutes(minutesUTC + equationOfTime + 4 * longitude)
		let hourAngle = trueSolarTime / 4 < 0 ? trueSolarTime / 4 + 180 : trueSolarTime / 4 - 180

		let latitudeRadians = degreesToRadians(latitude)
		let declinationRadians = degreesToRadians(declination)
		let hourAngleRadians = degreesToRadians(hourAngle)

		let cosineZenith = sin(latitudeRadians) * sin(declinationRadians)
			+ cos(latitudeRadians) * cos(declinationRadians) * cos(hourAngleRadians)

		let clampedCosineZenith = min(1, max(-1, cosineZenith))
		let zenith = radiansToDegrees(acos(clampedCosineZenith))
		return 90 - zenith
	}

	private static func julianDay(from date: Date) -> Double {
		date.timeIntervalSince1970 / 86_400.0 + 2_440_587.5
	}

	private static func utcMinutesSinceStartOfDay(for date: Date) -> Double {
		let calendar = Calendar(identifier: .gregorian)
		let components = calendar.dateComponents(in: TimeZone(secondsFromGMT: 0)!, from: date)

		let hour = Double(components.hour ?? 0)
		let minute = Double(components.minute ?? 0)
		let second = Double(components.second ?? 0)
		let nanosecond = Double(components.nanosecond ?? 0)

		return hour * 60 + minute + second / 60 + nanosecond / 60_000_000_000
	}

	private static func normalizedDegrees(_ degrees: Double) -> Double {
		let result = degrees.truncatingRemainder(dividingBy: 360)
		return result >= 0 ? result : result + 360
	}

	private static func normalizedMinutes(_ minutes: Double) -> Double {
		let result = minutes.truncatingRemainder(dividingBy: 1_440)
		return result >= 0 ? result : result + 1_440
	}

	private static func degreesToRadians(_ degrees: Double) -> Double {
		degrees * .pi / 180
	}

	private static func radiansToDegrees(_ radians: Double) -> Double {
		radians * 180 / .pi
	}
}
