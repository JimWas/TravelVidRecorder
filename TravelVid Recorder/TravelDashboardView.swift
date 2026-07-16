import SwiftUI
import MapKit
import CoreLocation
import Combine

struct TravelDashboardView: View {
    @ObservedObject private var locationManager = LocationManager.shared

    let speedUnit: TravelSpeedUnit
    let audioLevelDB: Float?
    let audioEnabled: Bool
    let isPreview: Bool

    @State private var mapPosition: MapCameraPosition = .automatic

    var body: some View {
        Group {
            if isPreview {
                previewLayout
            } else {
                GeometryReader { geometry in
                    if geometry.size.width > geometry.size.height {
                        landscapeLayout
                    } else {
                        portraitLayout
                    }
                }
            }
        }
        .background(dashboardBackground)
        .foregroundStyle(.white)
        .preferredColorScheme(.dark)
        .onAppear {
            guard !isPreview else { return }
            locationManager.startDashboardUpdates()
            updateMapPosition(locationManager.currentLocation)
        }
        .onDisappear {
            guard !isPreview else { return }
            locationManager.stopDashboardUpdates()
        }
        .onReceive(locationManager.$currentLocation.compactMap { $0 }) { location in
            guard !isPreview else { return }
            updateMapPosition(location)
        }
    }

    private var portraitLayout: some View {
        VStack(spacing: 16) {
            timeHeader
                .padding(.top, 10)

            HStack(spacing: 12) {
                speedCard
                headingCard
                noiseCard
            }
            .frame(height: 150)

            mapCard
                .frame(maxHeight: .infinity)
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 16)
    }

    private var landscapeLayout: some View {
        HStack(spacing: 16) {
            VStack(spacing: 12) {
                timeHeader
                HStack(spacing: 10) {
                    speedCard
                    headingCard
                    noiseCard
                }
            }
            .frame(maxWidth: 520)

            mapCard
        }
        .padding(16)
    }

    private var previewLayout: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 10) {
                Text("TRAVEL DASHBOARD")
                    .font(.caption2.weight(.bold))
                    .tracking(1.4)
                    .foregroundStyle(.cyan)

                TimelineView(.periodic(from: .now, by: 1)) { context in
                    Text(context.date.formatted(.dateTime.hour().minute().second()))
                        .font(.system(size: 28, weight: .semibold, design: .monospaced))
                }

                HStack(spacing: 14) {
                    previewMetric(value: "0", label: speedUnit.rawValue)
                    previewMetric(value: "N", label: "HEADING")
                    previewMetric(value: audioEnabled ? "--" : "OFF", label: "dBFS")
                }
            }

            RoundedRectangle(cornerRadius: 14)
                .fill(Color(red: 0.08, green: 0.17, blue: 0.19))
                .overlay {
                    VStack(spacing: 6) {
                        Image(systemName: "map.fill")
                            .font(.title2)
                            .foregroundStyle(.cyan)
                        Text("LIVE MAP")
                            .font(.caption2.bold())
                    }
                }
                .frame(width: 105)
        }
        .padding(16)
    }

    private var timeHeader: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            VStack(spacing: 4) {
                Text(context.date.formatted(.dateTime.hour().minute().second()))
                    .font(.system(size: 46, weight: .semibold, design: .monospaced))
                    .minimumScaleFactor(0.7)
                    .lineLimit(1)

                Text(context.date.formatted(.dateTime.weekday(.wide).month(.wide).day().year()))
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.white.opacity(0.68))
            }
            .frame(maxWidth: .infinity)
        }
    }

    private var speedCard: some View {
        metricCard(title: "SPEED", icon: "speedometer") {
            if let speed = displaySpeed {
                Text(speed.formatted(.number.precision(.fractionLength(0))))
                    .font(.system(size: 38, weight: .bold, design: .rounded))
                Text(speedUnit.rawValue)
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.cyan)
            } else {
                unavailableMetric(label: speedUnit.rawValue)
            }
        }
    }

    private var headingCard: some View {
        metricCard(title: "COMPASS", icon: "location.north.fill") {
            if let heading = displayHeading {
                Image(systemName: "location.north.fill")
                    .font(.title2)
                    .foregroundStyle(.cyan)
                    .rotationEffect(.degrees(heading))
                Text(cardinalDirection(for: heading))
                    .font(.system(size: 28, weight: .bold, design: .rounded))
                Text("\(Int(heading.rounded()))°")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.white.opacity(0.65))
            } else {
                unavailableMetric(label: "HEADING")
            }
        }
    }

    private var noiseCard: some View {
        metricCard(title: "NOISE", icon: "waveform") {
            if !audioEnabled {
                unavailableMetric(value: "OFF", label: "MIC")
            } else if let level = audioLevelDB {
                Text("\(abs(Int(level.rounded())))")
                    .font(.system(size: 34, weight: .bold, design: .rounded))
                Text("dBFS")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(noiseColor(level))
                GeometryReader { geometry in
                    Capsule()
                        .fill(.white.opacity(0.14))
                        .overlay(alignment: .leading) {
                            Capsule()
                                .fill(noiseColor(level))
                                .frame(width: geometry.size.width * noiseProgress(level))
                        }
                }
                .frame(height: 6)
            } else {
                unavailableMetric(label: "dBFS")
            }
        }
    }

    private var mapCard: some View {
        ZStack(alignment: .bottomLeading) {
            Map(position: $mapPosition, interactionModes: []) {
                if let coordinate = locationManager.currentLocation?.coordinate {
                    Marker("Current location", coordinate: coordinate)
                        .tint(.red)
                }
            }
            .mapStyle(.standard(elevation: .flat))

            if locationManager.currentLocation == nil {
                Color.black.opacity(0.52)
                VStack(spacing: 8) {
                    Image(systemName: "location.slash.fill")
                        .font(.title)
                    Text("Waiting for location")
                        .font(.headline)
                    Text("The live map appears when GPS is available.")
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.72))
                }
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }

            if let location = locationManager.currentLocation {
                Text(coordinateText(location.coordinate))
                    .font(.caption2.monospaced())
                    .padding(.horizontal, 10)
                    .padding(.vertical, 7)
                    .background(.black.opacity(0.72), in: Capsule())
                    .padding(10)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 20))
        .overlay {
            RoundedRectangle(cornerRadius: 20)
                .stroke(.white.opacity(0.16), lineWidth: 1)
        }
    }

    private var dashboardBackground: some View {
        LinearGradient(
            colors: [
                Color(red: 0.025, green: 0.07, blue: 0.10),
                Color(red: 0.035, green: 0.14, blue: 0.16),
                Color(red: 0.02, green: 0.055, blue: 0.075)
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
        .overlay {
            Canvas { context, size in
                let spacing: CGFloat = 28
                var path = Path()
                for x in stride(from: 0, through: size.width, by: spacing) {
                    path.move(to: CGPoint(x: x, y: 0))
                    path.addLine(to: CGPoint(x: x, y: size.height))
                }
                for y in stride(from: 0, through: size.height, by: spacing) {
                    path.move(to: CGPoint(x: 0, y: y))
                    path.addLine(to: CGPoint(x: size.width, y: y))
                }
                context.stroke(path, with: .color(.cyan.opacity(0.045)), lineWidth: 0.5)
            }
        }
        .ignoresSafeArea()
    }

    private func metricCard<Content: View>(
        title: String,
        icon: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(spacing: 7) {
            Label(title, systemImage: icon)
                .font(.caption2.weight(.bold))
                .tracking(0.8)
                .foregroundStyle(.white.opacity(0.62))

            content()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(10)
        .background(.white.opacity(0.075), in: RoundedRectangle(cornerRadius: 18))
        .overlay {
            RoundedRectangle(cornerRadius: 18)
                .stroke(.white.opacity(0.12), lineWidth: 1)
        }
    }

    private func previewMetric(value: String, label: String) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(value)
                .font(.headline.monospacedDigit())
            Text(label)
                .font(.system(size: 8, weight: .bold))
                .foregroundStyle(.white.opacity(0.55))
        }
    }

    private func unavailableMetric(value: String = "--", label: String) -> some View {
        VStack(spacing: 3) {
            Text(value)
                .font(.system(size: 28, weight: .bold, design: .rounded))
            Text(label)
                .font(.caption2.weight(.bold))
                .foregroundStyle(.white.opacity(0.5))
        }
    }

    private var displaySpeed: Double? {
        guard let location = locationManager.currentLocation,
              location.speed >= 0,
              abs(location.timestamp.timeIntervalSinceNow) < 30 else { return nil }
        return speedUnit.convert(metersPerSecond: location.speed)
    }

    private var displayHeading: CLLocationDirection? {
        guard let heading = locationManager.currentHeading else { return nil }
        let value = heading.trueHeading >= 0 ? heading.trueHeading : heading.magneticHeading
        return value >= 0 ? value : nil
    }

    private func updateMapPosition(_ location: CLLocation?) {
        guard let location else { return }
        mapPosition = .camera(MapCamera(
            centerCoordinate: location.coordinate,
            distance: 1_200,
            heading: displayHeading ?? 0,
            pitch: 0
        ))
    }

    private func cardinalDirection(for heading: CLLocationDirection) -> String {
        let directions = ["N", "NNE", "NE", "ENE", "E", "ESE", "SE", "SSE", "S", "SSW", "SW", "WSW", "W", "WNW", "NW", "NNW"]
        let index = Int((heading + 11.25) / 22.5) % directions.count
        return directions[index]
    }

    private func coordinateText(_ coordinate: CLLocationCoordinate2D) -> String {
        String(format: "%.5f, %.5f", coordinate.latitude, coordinate.longitude)
    }

    private func noiseProgress(_ level: Float) -> CGFloat {
        CGFloat(max(0, min(1, (level + 80) / 80)))
    }

    private func noiseColor(_ level: Float) -> Color {
        if level > -18 { return .red }
        if level > -38 { return .orange }
        return .green
    }
}
