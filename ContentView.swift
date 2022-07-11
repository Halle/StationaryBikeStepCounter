// Created by Halle Winkler on July/11/22. Copyright © 2022. All rights reserved.
// Requires Xcode 14.x and iOS 16.x, betas included.

import Charts
import CoreMotion
import SwiftUI

// MARK: - ContentView

/// ContentView is a collection of motion sensor UIs and a method of calling back to the model.

struct ContentView {
    @ObservedObject var manager: MotionManager
}

extension ContentView: View {
    var body: some View {
        VStack {
            ForEach(manager.sensors, id: \.sensorName) { sensor in
                SensorChart(sensor: sensor) { applyFilter, lowPassFilterFactor, quantizeFactor in
                    manager.updateFilteringFor(
                        sensor: sensor,
                        applyFilter: applyFilter,
                        lowPassFilterFactor: lowPassFilterFactor,
                        quantizeFactor: quantizeFactor)
                }
            }
        }.padding([.leading, .trailing], 6)
    }
}

// MARK: - SensorChart

/// I like to compose SwiftUI interfaces out of many small modules. But, there is a tension when it's a
/// small UI overall, and the modules will each have overhead from propagating state, binding and callbacks.

struct SensorChart {
    @State private var chartIsVisible = true
    @State private var breakOutAxes = false
    @State private var applyingFilter = false
    @State private var lowPassFilterFactor: Double = 0.75
    @State private var quantizeFactor: Double = 50
    var sensor: Sensor
    let updateFiltering: (Bool, Double, Double) -> Void
    private func toggleFiltering() {
        applyingFilter.toggle()
        updateFiltering(applyingFilter, lowPassFilterFactor, quantizeFactor)
    }
}

extension SensorChart: View {
    var body: some View {
/// Per-sensor controls: apply filtering to the waveform, hide and show sensor, break out the axes into separate charts.

        HStack {
            Text("\(sensor.sensorName)")
                .font(.system(size: 12, weight: .semibold, design: .default))
                .foregroundColor(chartIsVisible ? .black : .gray)
            Spacer()
            Button(action: toggleFiltering) {
                Image(systemName: applyingFilter ? "waveform.circle.fill" :
                    "waveform.circle")
            }
            .opacity(chartIsVisible ? 1.0 : 0.0)
            Button(action: { chartIsVisible.toggle() }) {
                Image(systemName: chartIsVisible ? "eye.circle.fill" :
                    "eye.slash.circle")
            }
            Button(action: { breakOutAxes.toggle() }) {
                Image(systemName: breakOutAxes ? "1.circle.fill" :
                    "3.circle.fill")
            }
            .opacity(chartIsVisible ? 1.0 : 0.0)
        }

/// Sensor charts, either one chart with three axes, or three charts with one axis. I love how concise Swift Charts can be.

        if chartIsVisible {
            if breakOutAxes {
                ForEach(sensor.axes, id: \.axisName) { series in
                    // Iterate charts from series
                    Chart {
                        ForEach(
                            Array(series.measurements.enumerated()),
                            id: \.offset) { index, datum in
                                LineMark(
                                    x: .value("Count", index),
                                    y: .value("Measurement", datum))
                            }
                    }
                    Text(
                        "Axis: \(series.axisName)\(applyingFilter ? "\t\tPeaks in window: \(series.peaks)" : "")")
                }
                .chartXAxis {
                    AxisMarks(values: .automatic(desiredCount: 0))
                }
            } else {
                Chart {
                    ForEach(sensor.axes, id: \.axisName) { series in
                        // Iterate series in a chart
                        ForEach(
                            Array(series.measurements.enumerated()),
                            id: \.offset) { index, datum in
                                LineMark(
                                    x: .value("Count", index),
                                    y: .value("Measurement", datum))
                            }
                            .foregroundStyle(by: .value("MeasurementName",
                                                        series.axisName))
                    }
                }.chartXAxis {
                    AxisMarks(values: .automatic(desiredCount: 0))
                }.chartYAxis {
                    AxisMarks(values: .automatic(desiredCount: 2))
                }
            }

/// in the separate three-axis view, you can set the low-pass filter factor and the quantizing factor if the waveform
/// filtering is on, and then once you can see your stationary pedaling reflected in the waveform, you can see how
/// many times per time window you're pedaling. With such an inevitably-noisy sensor environment, I already know
/// the low-pass filter factor will have to be very high, so I'm starting it at 0.75.
/// In the case of my exercise bike, the quantizing factor  that delivers very accurate peak-counting results on
/// gyroscope axis z is 520, which tells you these readings are really small numbers.

            if applyingFilter {
                Slider(
                    value: $lowPassFilterFactor,
                    in: 0.75 ... 1.0,
                    onEditingChanged: { _ in
                        updateFiltering(
                            true,
                            lowPassFilterFactor,
                            quantizeFactor)
                    })
                Text("Lowpass: \(String(format: "%.2f", lowPassFilterFactor))")
                    .font(.system(size: 12))
                    .frame(width: 100, alignment: .trailing)
                Slider(
                    value: $quantizeFactor,
                    in: 1 ... 600,
                    onEditingChanged: { _ in
                        updateFiltering(
                            true,
                            lowPassFilterFactor,
                            quantizeFactor)
                    })
                Text("Quantize: \(Int(quantizeFactor))")
                    .font(.system(size: 12))
                    .frame(width: 100, alignment: .trailing)
            }
        }
        Divider()
    }
}

// MARK: - MotionManager

/// MotionManager is the sensor management module.

class MotionManager: ObservableObject {
    // MARK: Lifecycle

    init() {
        self.manager = CMMotionManager()
        for name in SensorNames
            .allCases {
// self.sensors and func collectReadings(...) use SensorNames to index,
            if name ==
                .attitude {
// so if you change how one creates/derives a sensor index, change them both.
                sensors.append(ThreeAxisReadings(
                    sensorName: SensorNames.attitude.rawValue,
                    // The one exception to sensor axis naming:
                    axes: [
                        Axis(axisName: "Pitch"),
                        Axis(axisName: "Roll"),
                        Axis(axisName: "Yaw"),
                    ]))
            } else {
                sensors.append(ThreeAxisReadings(sensorName: name.rawValue))
            }
        }
        self.manager.deviceMotionUpdateInterval = sensorUpdateInterval
        self.manager.accelerometerUpdateInterval = sensorUpdateInterval
        self.manager.gyroUpdateInterval = sensorUpdateInterval
        self.manager.magnetometerUpdateInterval = sensorUpdateInterval
        self.startDeviceUpdates(manager: manager)
    }

    // MARK: Public

    public func updateFilteringFor( // Manage the callbacks from the UI
        sensor: ThreeAxisReadings,
        applyFilter: Bool,
        lowPassFilterFactor: Double,
        quantizeFactor: Double) {
        guard let index = sensors.firstIndex(of: sensor) else { return }
        DispatchQueue.main.async {
            self.sensors[index].applyFilter = applyFilter
            self.sensors[index].lowPassFilterFactor = lowPassFilterFactor
            self.sensors[index].quantizeFactor = quantizeFactor
        }
    }

    // MARK: Internal

    struct ThreeAxisReadings: Equatable {
        var sensorName: String // Usually, these have the same naming:
        var axes: [Axis] = [Axis(axisName: "x"), Axis(axisName: "y"),
                            Axis(axisName: "z")]
        var applyFilter: Bool = false
        var lowPassFilterFactor = 0.75
        var quantizeFactor = 1.0

        func lowPassFilter(lastReading: Double?, newReading: Double) -> Double {
            guard let lastReading else { return newReading }
            return self
                .lowPassFilterFactor * lastReading +
                (1.0 - self.lowPassFilterFactor) * newReading
        }
    }

    struct Axis: Hashable {
        var axisName: String
        var measurements: [Double] = []
        var peaks = 0
        var updatesSinceLastPeakCount = 0

/// I love sets, like, a lot. Enough that when I first thought "but what's an *elegant* way to know when it's a
/// good time to count the peaks again?" I thought of a one-liner set intersection, very semantic, very accurate to the
/// underlying question of freshness of sensor data, and it made me happy, and I smiled.
/// Anyway, a counter does the same thing with a 0s execution time, here's one of those:

        mutating func shouldCountPeaks()
            -> Bool { // Peaks are only counted once a second
            updatesSinceLastPeakCount += 1
            if updatesSinceLastPeakCount == MotionManager.updatesPerSecond {
                updatesSinceLastPeakCount = 0
                return true
            }
            return false
        }
    }

    @Published var sensors: [ThreeAxisReadings] = []

    // MARK: Private

    private enum SensorNames: String, CaseIterable {
        case attitude = "Attitude"
        case rotationRate = "Rotation Rate"
        case gravity = "Gravity"
        case userAcceleration = "User Acceleration"
        case acceleration = "Acceleration"
        case gyroscope = "Gyroscope"
        case magnetometer = "Magnetometer"
    }

    private static let updatesPerSecond: Int = 30

    private let motionQueue = OperationQueue() // Don't read sensors on main

    private let secondsToShow = 5 // Time window to observe
    private let sensorUpdateInterval = 1.0 / Double(updatesPerSecond)
    private let manager: CMMotionManager

    private func startDeviceUpdates(manager _: CMMotionManager) {
        self.manager
            .startDeviceMotionUpdates(to: motionQueue) { motion, error in
                self.collectReadings(motion, error)
            }
        self.manager
            .startAccelerometerUpdates(to: motionQueue) { motion, error in
                self.collectReadings(motion, error)
            }
        self.manager.startGyroUpdates(to: motionQueue) { motion, error in
            self.collectReadings(motion, error)
        }
        self.manager
            .startMagnetometerUpdates(to: motionQueue) { motion, error in
                self.collectReadings(motion, error)
            }
    }

    private func collectReadings(_ motion: CMLogItem?, _ error: Error?) {
        DispatchQueue.main.async { // Add new readings on main
            switch motion {
            case let motion as CMDeviceMotion:
                self.appendReadings(
                    [motion.attitude.pitch, motion.attitude.roll,
                     motion.attitude.yaw],
                    to: &self.sensors[SensorNames.attitude.index()])
                self.appendReadings(
                    [motion.rotationRate.x, motion.rotationRate.y,
                     motion.rotationRate.z],
                    to: &self.sensors[SensorNames.rotationRate.index()])
                self.appendReadings(
                    [motion.gravity.x, motion.gravity.y, motion.gravity.z],
                    to: &self.sensors[SensorNames.gravity.index()])
                self.appendReadings(
                    [motion.userAcceleration.x, motion.userAcceleration.y,
                     motion.userAcceleration.z],
                    to: &self.sensors[SensorNames.userAcceleration.index()])
            case let motion as CMAccelerometerData:
                self.appendReadings(
                    [motion.acceleration.x, motion.acceleration.y,
                     motion.acceleration.z],
                    to: &self.sensors[SensorNames.acceleration.index()])
            case let motion as CMGyroData:
                self.appendReadings(
                    [motion.rotationRate.x, motion.rotationRate.y,
                     motion.rotationRate.z],
                    to: &self.sensors[SensorNames.gyroscope.index()])
            case let motion as CMMagnetometerData:
                self.appendReadings(
                    [motion.magneticField.x, motion.magneticField.y,
                     motion.magneticField.z],
                    to: &self.sensors[SensorNames.magnetometer.index()])
            default:
                print(error != nil ? "Error: \(String(describing: error))" :
                    "Unknown device")
            }
        }
    }

    private func appendReadings(
        _ newReadings: [Double],
        to threeAxisReadings: inout ThreeAxisReadings) {
        for index in 0 ..< threeAxisReadings.axes
            .count { // For each of the axes
            var axis = threeAxisReadings.axes[index]
            let newReading = newReadings[index]

            axis.measurements
                .append(threeAxisReadings
                    .applyFilter ? // Append new reading, as-is or filtered
                    threeAxisReadings.lowPassFilter(
                        lastReading: axis.measurements.last,
                        newReading: newReading) : newReading)

            if threeAxisReadings.applyFilter,
               axis
               .shouldCountPeaks() {
                // And occasionally count peaks if filtering
                axis.peaks = countPeaks(
                    in: axis.measurements,
                    quantizeFactor: threeAxisReadings.quantizeFactor)
            }

            if axis.measurements
                .count >=
                Int(1.0 / self
                    .sensorUpdateInterval * Double(self.secondsToShow)) {
                axis.measurements
                    .removeFirst() // trim old data to keep our moving window representing secondsToShow
            }
            threeAxisReadings.axes[index] = axis
        }
    }

    private func countPeaks(
        in readings: [Double],
        quantizeFactor: Double) -> Int { // Count local maxima
        let quantizedreadings = readings.map { Int($0 * quantizeFactor) }
        // Quantize into small Ints (instead of extremely small Doubles) to remove detail from little component waves

        var ascendingWave = true
        var numberOfPeaks = 0
        var lastReading = 0

        for reading in quantizedreadings {
            if ascendingWave == true,
               lastReading >
               reading { // If we were going up but it stopped being true,
                numberOfPeaks += 1 // we just passed a peak,
                ascendingWave = false // and we're going down.
            } else if lastReading <
                reading {
                // If we just started to or continue to go up, note we're ascending.
                ascendingWave = true
            }
            lastReading = reading
        }
        return numberOfPeaks
    }
}

extension CaseIterable where Self: Equatable {
    func index() -> Self.AllCases
        .Index {
        // Force-unwrap of index of enum case in CaseIterable always succeeds.
        return Self.allCases.firstIndex(of: self)!
    }
}

typealias Sensor = MotionManager.ThreeAxisReadings
