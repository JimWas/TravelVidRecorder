import SwiftUI

struct WorldCity {
    let name: String
    let region: String
    let timeZoneID: String
}

struct WorldClockView: View {
    @State private var now = Date()
    let timer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    let cities: [WorldCity] = [
        WorldCity(name: "Siem Reap",       region: "Cambodia",       timeZoneID: "Asia/Phnom_Penh"),
        WorldCity(name: "Ho Chi Minh City",region: "Vietnam",        timeZoneID: "Asia/Ho_Chi_Minh"),
        WorldCity(name: "Bangkok",         region: "Thailand",       timeZoneID: "Asia/Bangkok"),
        WorldCity(name: "Jakarta",         region: "Indonesia",      timeZoneID: "Asia/Jakarta"),
        WorldCity(name: "Kuala Lumpur",    region: "Malaysia",       timeZoneID: "Asia/Kuala_Lumpur"),
        WorldCity(name: "Singapore",       region: "Singapore",      timeZoneID: "Asia/Singapore"),
        WorldCity(name: "Manila",          region: "Philippines",    timeZoneID: "Asia/Manila"),
        WorldCity(name: "Taipei",          region: "Taiwan",         timeZoneID: "Asia/Taipei"),
        WorldCity(name: "Hong Kong",       region: "Hong Kong",      timeZoneID: "Asia/Hong_Kong"),
        WorldCity(name: "Shanghai",        region: "China",          timeZoneID: "Asia/Shanghai"),
        WorldCity(name: "Beijing",         region: "China",          timeZoneID: "Asia/Shanghai"),
        WorldCity(name: "Seoul",           region: "South Korea",    timeZoneID: "Asia/Seoul"),
        WorldCity(name: "Tokyo",           region: "Japan",          timeZoneID: "Asia/Tokyo"),
        WorldCity(name: "Mumbai",          region: "India",          timeZoneID: "Asia/Kolkata"),
        WorldCity(name: "Delhi",           region: "India",          timeZoneID: "Asia/Kolkata"),
        WorldCity(name: "Dubai",           region: "United Arab Emirates", timeZoneID: "Asia/Dubai"),
        WorldCity(name: "Riyadh",          region: "Saudi Arabia",   timeZoneID: "Asia/Riyadh"),
        WorldCity(name: "Nairobi",         region: "Kenya",          timeZoneID: "Africa/Nairobi"),
        WorldCity(name: "Moscow",          region: "Russia",         timeZoneID: "Europe/Moscow"),
        WorldCity(name: "Istanbul",        region: "Turkey",         timeZoneID: "Europe/Istanbul"),
        WorldCity(name: "Athens",          region: "Greece",         timeZoneID: "Europe/Athens"),
        WorldCity(name: "Cairo",           region: "Egypt",          timeZoneID: "Africa/Cairo"),
        WorldCity(name: "Johannesburg",    region: "South Africa",   timeZoneID: "Africa/Johannesburg"),
        WorldCity(name: "Rome",            region: "Italy",          timeZoneID: "Europe/Rome"),
        WorldCity(name: "Paris",           region: "France",         timeZoneID: "Europe/Paris"),
        WorldCity(name: "Berlin",          region: "Germany",        timeZoneID: "Europe/Berlin"),
        WorldCity(name: "Amsterdam",       region: "Netherlands",    timeZoneID: "Europe/Amsterdam"),
        WorldCity(name: "Zurich",          region: "Switzerland",    timeZoneID: "Europe/Zurich"),
        WorldCity(name: "Madrid",          region: "Spain",          timeZoneID: "Europe/Madrid"),
        WorldCity(name: "London",          region: "United Kingdom", timeZoneID: "Europe/London"),
        WorldCity(name: "São Paulo",       region: "Brazil",         timeZoneID: "America/Sao_Paulo"),
        WorldCity(name: "Buenos Aires",    region: "Argentina",      timeZoneID: "America/Argentina/Buenos_Aires"),
        WorldCity(name: "Lima",            region: "Peru",           timeZoneID: "America/Lima"),
        WorldCity(name: "Bogotá",          region: "Colombia",       timeZoneID: "America/Bogota"),
        WorldCity(name: "New York",        region: "United States",  timeZoneID: "America/New_York"),
        WorldCity(name: "Toronto",         region: "Canada",         timeZoneID: "America/Toronto"),
        WorldCity(name: "Chicago",         region: "United States",  timeZoneID: "America/Chicago"),
        WorldCity(name: "Mexico City",     region: "Mexico",         timeZoneID: "America/Mexico_City"),
        WorldCity(name: "Denver",          region: "United States",  timeZoneID: "America/Denver"),
        WorldCity(name: "Los Angeles",     region: "United States",  timeZoneID: "America/Los_Angeles"),
        WorldCity(name: "Vancouver",       region: "Canada",         timeZoneID: "America/Vancouver"),
        WorldCity(name: "Sydney",          region: "Australia",      timeZoneID: "Australia/Sydney"),
        WorldCity(name: "Melbourne",       region: "Australia",      timeZoneID: "Australia/Melbourne"),
        WorldCity(name: "Auckland",        region: "New Zealand",    timeZoneID: "Pacific/Auckland"),
    ]

    var body: some View {
        ZStack(alignment: .top) {
            Color.black.ignoresSafeArea()

            VStack(spacing: 0) {
                // Navigation bar style header
                HStack {
                    Spacer()
                    Text("World Clock")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundColor(.white)
                    Spacer()
                }
                .frame(height: 44)
                .padding(.horizontal, 16)
                .background(Color.black)

                // Large title
                HStack {
                    Text("World Clock")
                        .font(.system(size: 34, weight: .bold))
                        .foregroundColor(.white)
                    Spacer()
                }
                .padding(.horizontal, 16)
                .padding(.top, 8)
                .padding(.bottom, 12)
                .background(Color.black)

                // City list
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(cities, id: \.name) { city in
                            CityRowView(city: city, now: now)
                            Rectangle()
                                .fill(Color(white: 0.2))
                                .frame(height: 0.5)
                                .padding(.leading, 16)
                        }
                    }
                }
            }
        }
        .onReceive(timer) { date in
            now = date
        }
    }
}

struct CityRowView: View {
    let city: WorldCity
    let now: Date

    private var cityTimeZone: TimeZone {
        TimeZone(identifier: city.timeZoneID) ?? TimeZone.current
    }

    private var timeComponents: (hours: String, minutes: String, ampm: String) {
        let formatter = DateFormatter()
        formatter.timeZone = cityTimeZone
        formatter.locale = Locale(identifier: "en_US")

        formatter.dateFormat = "h"
        let hours = formatter.string(from: now)

        formatter.dateFormat = "mm"
        let minutes = formatter.string(from: now)

        formatter.dateFormat = "a"
        let ampm = formatter.string(from: now).uppercased()

        return (hours, minutes, ampm)
    }

    private var offsetLabel: String {
        let localTZ = TimeZone.current
        let cityTZ = cityTimeZone

        let localOffset = localTZ.secondsFromGMT(for: now)
        let cityOffset = cityTZ.secondsFromGMT(for: now)
        let diffSeconds = cityOffset - localOffset
        let diffHours = diffSeconds / 3600
        let diffMinutes = abs((diffSeconds % 3600) / 60)

        // Determine day relationship
        let localCalendar = Calendar.current
        var cityCalendar = Calendar.current
        cityCalendar.timeZone = cityTZ

        let localDayOfYear = localCalendar.ordinality(of: .day, in: .year, for: now) ?? 0
        let cityDayOfYear = cityCalendar.ordinality(of: .day, in: .year, for: now) ?? 0

        let dayDiff = cityDayOfYear - localDayOfYear

        let dayLabel: String
        if dayDiff == 0 {
            dayLabel = "TODAY"
        } else if dayDiff == 1 || dayDiff == -364 || dayDiff == -365 {
            dayLabel = "TOMORROW"
        } else {
            dayLabel = "YESTERDAY"
        }

        if diffSeconds == 0 {
            return "SAME TIME"
        }

        let sign = diffSeconds > 0 ? "+" : "-"
        let absHours = abs(diffHours)

        if diffMinutes == 0 {
            let hrLabel = absHours == 1 ? "HR" : "HRS"
            return "\(dayLabel), \(sign)\(absHours)\(hrLabel)"
        } else if absHours == 0 {
            return "\(dayLabel), \(sign)\(diffMinutes)MIN"
        } else {
            return "\(dayLabel), \(sign)\(absHours)HR \(diffMinutes)MIN"
        }
    }

    var body: some View {
        HStack(alignment: .center, spacing: 0) {
            // Left side: city name, region, offset
            VStack(alignment: .leading, spacing: 2) {
                Text(offsetLabel)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(Color(white: 0.55))
                    .tracking(0.3)
                Text(city.name)
                    .font(.system(size: 24, weight: .light))
                    .foregroundColor(.white)
                Text(city.region)
                    .font(.system(size: 15, weight: .regular))
                    .foregroundColor(Color(white: 0.55))
            }
            .padding(.vertical, 14)

            Spacer()

            // Right side: digital time
            HStack(alignment: .firstTextBaseline, spacing: 2) {
                let t = timeComponents
                Text("\(t.hours):\(t.minutes)")
                    .font(.system(size: 52, weight: .thin))
                    .foregroundColor(.white)
                    .monospacedDigit()
                Text(t.ampm)
                    .font(.system(size: 17, weight: .light))
                    .foregroundColor(.white)
                    .padding(.bottom, 4)
            }
        }
        .padding(.horizontal, 16)
        .background(Color.black)
    }
}

#Preview {
    WorldClockView()
}
