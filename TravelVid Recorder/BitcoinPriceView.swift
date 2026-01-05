//
//  BitcoinPriceView.swift
//  TravelVid Recorder
//
//  Created by Jim Washkau on 1/5/26.
//


import SwiftUI

struct BitcoinPriceView: View {
    @StateObject private var priceTracker = BitcoinPriceTracker()
    
    var body: some View {
        ZStack {
            // Background
            Color.black
                .ignoresSafeArea()
            
            ScrollView {
                VStack(spacing: 0) {
                    // Header
                    header
                    
                    // Main Price Card
                    priceCard
                    
                    // Chart
                    chartSection
                    
                    // Stats Grid
                    statsGrid
                    
                    // Market Info
                    marketInfo
                    
                    Spacer(minLength: 40)
                }
            }
        }
        .onAppear {
            priceTracker.startUpdating()
        }
        .onDisappear {
            priceTracker.stopUpdating()
        }
    }
    
    private var header: some View {
        HStack {
            Image(systemName: "bitcoinsign.circle.fill")
                .font(.title)
                .foregroundColor(.orange)
            
            Text("Bitcoin")
                .font(.title2.bold())
                .foregroundColor(.white)
            
            Spacer()
            
            Text("BTC/USD")
                .font(.subheadline)
                .foregroundColor(.gray)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(Color.white.opacity(0.1))
                .cornerRadius(8)
        }
        .padding()
    }
    
    private var priceCard: some View {
        VStack(spacing: 8) {
            // Current Price
            Text(priceTracker.formattedPrice)
                .font(.system(size: 48, weight: .bold, design: .rounded))
                .foregroundColor(.white)
            
            // Change
            HStack(spacing: 8) {
                Image(systemName: priceTracker.isPositive ? "arrow.up.right" : "arrow.down.right")
                Text(priceTracker.formattedChange)
                Text("(\(priceTracker.formattedPercentage))")
            }
            .font(.title3.bold())
            .foregroundColor(priceTracker.isPositive ? .green : .red)
            .padding(.horizontal, 20)
            .padding(.vertical, 10)
            .background(
                (priceTracker.isPositive ? Color.green : Color.red).opacity(0.2)
            )
            .cornerRadius(12)
        }
        .padding()
        .frame(maxWidth: .infinity)
        .background(Color.white.opacity(0.05))
        .cornerRadius(20)
        .padding(.horizontal)
    }
    
    private var chartSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Time Period Selector
            HStack {
                ForEach(["1H", "24H", "1W", "1M", "1Y"], id: \.self) { period in
                    Text(period)
                        .font(.caption.bold())
                        .foregroundColor(period == "24H" ? .orange : .gray)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(
                            period == "24H" ? Color.orange.opacity(0.2) : Color.clear
                        )
                        .cornerRadius(8)
                }
            }
            .padding(.horizontal)
            
            // Chart
            GeometryReader { geometry in
                ZStack {
                    // Grid lines
                    VStack(spacing: 0) {
                        ForEach(0..<5) { _ in
                            Divider()
                                .background(Color.white.opacity(0.1))
                            Spacer()
                        }
                    }
                    
                    // Price line
                    PriceChart(prices: priceTracker.priceHistory)
                        .stroke(
                            LinearGradient(
                                gradient: Gradient(colors: [.orange, .orange.opacity(0.6)]),
                                startPoint: .leading,
                                endPoint: .trailing
                            ),
                            lineWidth: 2
                        )
                    
                    // Filled area under line
                    PriceChart(prices: priceTracker.priceHistory)
                        .fill(
                            LinearGradient(
                                gradient: Gradient(colors: [
                                    Color.orange.opacity(0.3),
                                    Color.orange.opacity(0.0)
                                ]),
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )
                }
            }
            .frame(height: 200)
            .padding(.horizontal)
        }
        .padding(.vertical)
    }
    
    private var statsGrid: some View {
        VStack(spacing: 12) {
            HStack(spacing: 12) {
                StatBox(title: "24h High", value: priceTracker.formattedHigh, color: .green)
                StatBox(title: "24h Low", value: priceTracker.formattedLow, color: .red)
            }
            
            HStack(spacing: 12) {
                StatBox(title: "24h Volume", value: "$52.8B", color: .blue)
                StatBox(title: "Market Cap", value: "$1.95T", color: .purple)
            }
        }
        .padding(.horizontal)
    }
    
    private var marketInfo: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Market Information")
                .font(.headline)
                .foregroundColor(.white)
            
            InfoRow(icon: "chart.line.uptrend.xyaxis", title: "Circulating Supply", value: "19.6M BTC")
            InfoRow(icon: "infinity", title: "Max Supply", value: "21.0M BTC")
            InfoRow(icon: "clock", title: "Last Updated", value: priceTracker.lastUpdateTime)
        }
        .padding()
        .background(Color.white.opacity(0.05))
        .cornerRadius(15)
        .padding(.horizontal)
        .padding(.top)
    }
}

struct StatBox: View {
    let title: String
    let value: String
    let color: Color
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.caption)
                .foregroundColor(.gray)
            Text(value)
                .font(.title3.bold())
                .foregroundColor(color)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(Color.white.opacity(0.05))
        .cornerRadius(12)
    }
}

struct InfoRow: View {
    let icon: String
    let title: String
    let value: String
    
    var body: some View {
        HStack {
            Image(systemName: icon)
                .foregroundColor(.orange)
                .frame(width: 24)
            
            Text(title)
                .foregroundColor(.gray)
            
            Spacer()
            
            Text(value)
                .foregroundColor(.white)
                .bold()
        }
        .font(.subheadline)
    }
}

// MARK: - Price Chart Shape
struct PriceChart: Shape {
    let prices: [Double]
    
    func path(in rect: CGRect) -> Path {
        guard prices.count > 1 else { return Path() }
        
        var path = Path()
        
        let minPrice = prices.min() ?? 0
        let maxPrice = prices.max() ?? 1
        let priceRange = maxPrice - minPrice
        
        let stepX = rect.width / CGFloat(prices.count - 1)
        
        // Start at bottom left for fill
        path.move(to: CGPoint(x: 0, y: rect.height))
        
        // Draw the price line
        for (index, price) in prices.enumerated() {
            let x = CGFloat(index) * stepX
            let normalizedPrice = (price - minPrice) / priceRange
            let y = rect.height - (CGFloat(normalizedPrice) * rect.height)
            
            if index == 0 {
                path.addLine(to: CGPoint(x: x, y: y))
            } else {
                path.addLine(to: CGPoint(x: x, y: y))
            }
        }
        
        // Complete the fill by going to bottom right
        path.addLine(to: CGPoint(x: rect.width, y: rect.height))
        path.closeSubpath()
        
        return path
    }
}

// MARK: - Price Tracker Logic
@MainActor
class BitcoinPriceTracker: ObservableObject {
    @Published var currentPrice: Double
    @Published var priceHistory: [Double] = []
    @Published var dailyHigh: Double
    @Published var dailyLow: Double
    @Published var dailyChange: Double = 0
    @Published var lastUpdateTime: String = ""
    
    private var timer: Timer?
    private let basePrice: Double
    
    var isPositive: Bool { dailyChange >= 0 }
    
    var formattedPrice: String {
        String(format: "$%.2f", currentPrice)
    }
    
    var formattedChange: String {
        String(format: "$%.2f", abs(dailyChange))
    }
    
    var formattedPercentage: String {
        let percent = (dailyChange / (currentPrice - dailyChange)) * 100
        return String(format: "%.2f%%", abs(percent))
    }
    
    var formattedHigh: String {
        String(format: "$%.2f", dailyHigh)
    }
    
    var formattedLow: String {
        String(format: "$%.2f", dailyLow)
    }
    
    init() {
        // Random base price between $90,000 and $100,000
        self.basePrice = Double.random(in: 90000...100000)
        self.currentPrice = basePrice
        self.dailyHigh = basePrice + Double.random(in: 500...2000)
        self.dailyLow = basePrice - Double.random(in: 500...2000)
        
        // Initialize with some history
        generateInitialHistory()
        updateTime()
    }
    
    private func generateInitialHistory() {
        // Generate 50 data points for the chart
        for i in 0..<50 {
            let variation = sin(Double(i) * 0.2) * 800 + Double.random(in: -400...400)
            let price = basePrice + variation
            priceHistory.append(price)
        }
    }
    
    func startUpdating() {
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { [weak self] _ in
            self?.updatePrice()
        }
    }
    
    func stopUpdating() {
        timer?.invalidate()
    }
    
    private func updatePrice() {
        // Small random price fluctuations
        let change = Double.random(in: -200...200)
        let newPrice = currentPrice + change
        
        // Keep price within reasonable bounds
        if newPrice > 85000 && newPrice < 105000 {
            currentPrice = newPrice
            
            // Update daily high/low
            if newPrice > dailyHigh {
                dailyHigh = newPrice
            }
            if newPrice < dailyLow {
                dailyLow = newPrice
            }
            
            // Update daily change
            dailyChange = currentPrice - basePrice
            
            // Update price history
            priceHistory.append(newPrice)
            if priceHistory.count > 50 {
                priceHistory.removeFirst()
            }
            
            updateTime()
        }
    }
    
    private func updateTime() {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss"
        lastUpdateTime = formatter.string(from: Date())
    }
    
    deinit {
        timer?.invalidate()
    }
}

#Preview {
    BitcoinPriceView()
}