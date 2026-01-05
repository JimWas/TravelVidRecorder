import SwiftUI

struct FlappyBirdView: View {
    @StateObject private var game = FlappyBirdGame()
    
    var body: some View {
        GeometryReader { geometry in
            ZStack {
                // Background
                LinearGradient(
                    gradient: Gradient(colors: [Color(red: 0.53, green: 0.81, blue: 0.92), Color(red: 0.4, green: 0.7, blue: 0.9)]),
                    startPoint: .top,
                    endPoint: .bottom
                )
                .ignoresSafeArea()
                
                // Pipes
                ForEach(game.pipes) { pipe in
                    PipeView(pipe: pipe, screenHeight: geometry.size.height)
                }
                
                // Bird
                BirdView()
                    .position(x: game.birdX, y: game.birdY)
                
                // Score & Difficulty Indicator
                VStack {
                    HStack {
                        // Difficulty Badge
                        Text(game.difficulty.rawValue)
                            .font(.caption.bold())
                            .foregroundColor(.white)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 5)
                            .background(game.difficulty.color.opacity(0.8))
                            .cornerRadius(12)
                            .padding(.leading, 20)
                        
                        Spacer()
                        
                        // Score
                        Text("\(game.score)")
                            .font(.system(size: 60, weight: .bold))
                            .foregroundColor(.white)
                            .shadow(color: .black.opacity(0.3), radius: 2, x: 2, y: 2)
                        
                        Spacer()
                        
                        // Balance space
                        Color.clear.frame(width: 80)
                    }
                    .padding(.top, 60)
                    
                    Spacer()
                }
                
                // Game Over Screen
                if game.gameState == .gameOver {
                    GameOverView(score: game.score, highScore: game.highScore, difficulty: game.difficulty) {
                        game.restart()
                    }
                }
                
                // Start Screen
                if game.gameState == .ready {
                    StartView(difficulty: $game.difficulty) {
                        game.start()
                    }
                }
            }
            .onAppear {
                game.setupGame(screenHeight: geometry.size.height, screenWidth: geometry.size.width)
            }
            .onTapGesture {
                game.flap()
            }
        }
    }
}

struct BirdView: View {
    var body: some View {
        Circle()
            .fill(Color.yellow)
            .frame(width: 35, height: 35)
            .overlay(
                Circle()
                    .stroke(Color.orange, lineWidth: 2)
            )
            .overlay(
                HStack(spacing: 6) {
                    Circle()
                        .fill(Color.white)
                        .frame(width: 8, height: 8)
                        .overlay(
                            Circle()
                                .fill(Color.black)
                                .frame(width: 4, height: 4)
                        )
                    Circle()
                        .fill(Color.white)
                        .frame(width: 8, height: 8)
                        .overlay(
                            Circle()
                                .fill(Color.black)
                                .frame(width: 4, height: 4)
                        )
                }
                .offset(x: 4, y: -4)
            )
    }
}

struct PipeView: View {
    let pipe: Pipe
    let screenHeight: CGFloat
    
    var body: some View {
        ZStack(alignment: .leading) {
            // Top pipe
            Rectangle()
                .fill(
                    LinearGradient(
                        gradient: Gradient(colors: [Color.green, Color.green.opacity(0.8)]),
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                )
                .frame(width: pipe.width, height: pipe.topHeight)
                .position(x: pipe.x, y: pipe.topHeight / 2)
                .overlay(
                    Rectangle()
                        .stroke(Color.green.opacity(0.6), lineWidth: 2)
                        .frame(width: pipe.width, height: pipe.topHeight)
                        .position(x: pipe.x, y: pipe.topHeight / 2)
                )
            
            // Bottom pipe
            Rectangle()
                .fill(
                    LinearGradient(
                        gradient: Gradient(colors: [Color.green, Color.green.opacity(0.8)]),
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                )
                .frame(width: pipe.width, height: screenHeight - pipe.topHeight - pipe.gap)
                .position(x: pipe.x, y: pipe.topHeight + pipe.gap + (screenHeight - pipe.topHeight - pipe.gap) / 2)
                .overlay(
                    Rectangle()
                        .stroke(Color.green.opacity(0.6), lineWidth: 2)
                        .frame(width: pipe.width, height: screenHeight - pipe.topHeight - pipe.gap)
                        .position(x: pipe.x, y: pipe.topHeight + pipe.gap + (screenHeight - pipe.topHeight - pipe.gap) / 2)
                )
        }
    }
}

struct GameOverView: View {
    let score: Int
    let highScore: Int
    let difficulty: Difficulty
    let onRestart: () -> Void
    
    var body: some View {
        VStack(spacing: 20) {
            Text("Game Over!")
                .font(.system(size: 50, weight: .bold))
                .foregroundColor(.white)
                .shadow(color: .black.opacity(0.5), radius: 3, x: 2, y: 2)
            
            // Difficulty badge
            Text(difficulty.rawValue)
                .font(.caption.bold())
                .foregroundColor(.white)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(difficulty.color)
                .cornerRadius(12)
            
            VStack(spacing: 10) {
                Text("Score: \(score)")
                    .font(.system(size: 30, weight: .semibold))
                    .foregroundColor(.white)
                
                Text("Best: \(highScore)")
                    .font(.system(size: 25))
                    .foregroundColor(.white.opacity(0.9))
            }
            
            Button(action: onRestart) {
                Text("Restart")
                    .font(.system(size: 25, weight: .bold))
                    .foregroundColor(.white)
                    .padding(.horizontal, 40)
                    .padding(.vertical, 15)
                    .background(Color.orange)
                    .cornerRadius(15)
                    .shadow(radius: 5)
            }
            .padding(.top, 20)
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 20)
                .fill(Color.black.opacity(0.7))
        )
    }
}

struct StartView: View {
    @Binding var difficulty: Difficulty
    let onStart: () -> Void
    
    var body: some View {
        VStack(spacing: 30) {
            Text("Flappy Bird")
                .font(.system(size: 50, weight: .bold))
                .foregroundColor(.white)
                .shadow(color: .black.opacity(0.5), radius: 3, x: 2, y: 2)
            
            // Difficulty Selector
            VStack(spacing: 12) {
                Text("Difficulty")
                    .font(.headline)
                    .foregroundColor(.white.opacity(0.9))
                
                Picker("Difficulty", selection: $difficulty) {
                    ForEach(Difficulty.allCases) { diff in
                        Text(diff.rawValue).tag(diff)
                    }
                }
                .pickerStyle(.segmented)
                .frame(width: 280)
                
                // Difficulty description
                Text(difficulty.description)
                    .font(.caption)
                    .foregroundColor(.white.opacity(0.8))
                    .multilineTextAlignment(.center)
                    .frame(width: 280)
            }
            .padding()
            .background(
                RoundedRectangle(cornerRadius: 15)
                    .fill(Color.white.opacity(0.1))
            )
            
            Text("Tap to Flap")
                .font(.system(size: 20))
                .foregroundColor(.white.opacity(0.9))
            
            Button(action: onStart) {
                Text("Start")
                    .font(.system(size: 25, weight: .bold))
                    .foregroundColor(.white)
                    .padding(.horizontal, 50)
                    .padding(.vertical, 15)
                    .background(difficulty.color)
                    .cornerRadius(15)
                    .shadow(radius: 5)
            }
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 20)
                .fill(Color.black.opacity(0.7))
        )
    }
}

// MARK: - Game Logic

enum GameState {
    case ready, playing, gameOver
}

enum Difficulty: String, CaseIterable, Identifiable {
    case easy = "Easy"
    case medium = "Medium"
    case hard = "Hard"
    
    var id: String { rawValue }
    
    var color: Color {
        switch self {
        case .easy: return .green
        case .medium: return .orange
        case .hard: return .red
        }
    }
    
    var description: String {
        switch self {
        case .easy: return "Large gaps, slow speed - Perfect for beginners!"
        case .medium: return "Balanced gameplay - A fair challenge"
        case .hard: return "Small gaps, fast speed - For experts only!"
        }
    }
    
    // Game parameters
    var gapSize: (min: CGFloat, max: CGFloat) {
        switch self {
        case .easy: return (220, 240)
        case .medium: return (180, 200)
        case .hard: return (150, 170)
        }
    }
    
    var gravity: CGFloat {
        switch self {
        case .easy: return 0.45
        case .medium: return 0.6
        case .hard: return 0.75
        }
    }
    
    var pipeSpeed: CGFloat {
        switch self {
        case .easy: return 2.5
        case .medium: return 3.5
        case .hard: return 4.5
        }
    }
    
    var flapStrength: CGFloat {
        switch self {
        case .easy: return -10
        case .medium: return -11
        case .hard: return -12
        }
    }
}

struct Pipe: Identifiable {
    let id = UUID()
    var x: CGFloat
    let topHeight: CGFloat
    let gap: CGFloat
    let width: CGFloat = 60
    var passed = false
}

@MainActor
class FlappyBirdGame: ObservableObject {
    @Published var birdY: CGFloat = 0
    @Published var birdX: CGFloat = 0
    @Published var pipes: [Pipe] = []
    @Published var score: Int = 0
    @Published var gameState: GameState = .ready
    @Published var difficulty: Difficulty {
        didSet {
            // Save difficulty preference
            UserDefaults.standard.set(difficulty.rawValue, forKey: "flappyBirdDifficulty")
        }
    }
    @Published var highScore: Int = UserDefaults.standard.integer(forKey: "flappyBirdHighScore")
    
    private var birdVelocity: CGFloat = 0
    private var screenHeight: CGFloat = 0
    private var screenWidth: CGFloat = 0
    private var timer: Timer?
    
    let pipeSpacing: CGFloat = 280
    let birdSize: CGFloat = 35
    let collisionMargin: CGFloat = 5
    
    init() {
        // Load saved difficulty or default to Easy
        if let savedDiff = UserDefaults.standard.string(forKey: "flappyBirdDifficulty"),
           let diff = Difficulty(rawValue: savedDiff) {
            self.difficulty = diff
        } else {
            self.difficulty = .easy
        }
    }
    
    func setupGame(screenHeight: CGFloat, screenWidth: CGFloat) {
        self.screenHeight = screenHeight
        self.screenWidth = screenWidth
        self.birdY = screenHeight / 2
        self.birdX = screenWidth * 0.3
    }
    
    func start() {
        gameState = .playing
        birdY = screenHeight / 2
        birdVelocity = 0
        score = 0
        pipes.removeAll()
        
        // Generate initial pipes
        for i in 0..<3 {
            addPipe(at: screenWidth + CGFloat(i) * pipeSpacing + 100)
        }
        
        // Start game loop
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 1/60, repeats: true) { [weak self] _ in
            self?.update()
        }
    }
    
    func flap() {
        guard gameState == .playing else { return }
        birdVelocity = difficulty.flapStrength
    }
    
    func restart() {
        gameState = .ready
        timer?.invalidate()
        pipes.removeAll()
    }
    
    private func update() {
        guard gameState == .playing else { return }
        
        // Update bird physics with difficulty-based gravity
        birdVelocity += difficulty.gravity
        birdY += birdVelocity
        
        // Check boundaries with margin
        if birdY <= birdSize/2 + 20 || birdY >= screenHeight - birdSize/2 - 20 {
            gameOver()
            return
        }
        
        // Update pipes with difficulty-based speed
        for i in pipes.indices {
            pipes[i].x -= difficulty.pipeSpeed
            
            // Check if pipe passed bird (for scoring)
            let pipeRight = pipes[i].x + pipes[i].width/2
            if !pipes[i].passed && pipeRight < birdX {
                pipes[i].passed = true
                score += 1
            }
            
            // Check collision
            if checkCollision(with: pipes[i]) {
                gameOver()
                return
            }
        }
        
        // Remove off-screen pipes and add new ones
        pipes.removeAll { $0.x < -100 }
        
        if let lastPipe = pipes.last, lastPipe.x < screenWidth - pipeSpacing {
            addPipe(at: screenWidth + 50)
        }
    }
    
    private func addPipe(at x: CGFloat) {
        let gapRange = difficulty.gapSize
        let gap = CGFloat.random(in: gapRange.min...gapRange.max)
        
        let minTopHeight: CGFloat = 120
        let maxTopHeight = screenHeight - gap - 120
        let topHeight = CGFloat.random(in: minTopHeight...maxTopHeight)
        
        pipes.append(Pipe(x: x, topHeight: topHeight, gap: gap))
    }
    
    private func checkCollision(with pipe: Pipe) -> Bool {
        // Bird boundaries with collision margin
        let birdLeft = birdX - birdSize/2 + collisionMargin
        let birdRight = birdX + birdSize/2 - collisionMargin
        let birdTop = birdY - birdSize/2 + collisionMargin
        let birdBottom = birdY + birdSize/2 - collisionMargin
        
        // Pipe boundaries
        let pipeLeft = pipe.x - pipe.width/2
        let pipeRight = pipe.x + pipe.width/2
        let topPipeBottom = pipe.topHeight
        let bottomPipeTop = pipe.topHeight + pipe.gap
        
        // Check horizontal overlap first
        let horizontalOverlap = birdRight > pipeLeft && birdLeft < pipeRight
        
        if horizontalOverlap {
            // Check if bird hits top pipe
            if birdTop < topPipeBottom {
                return true
            }
            // Check if bird hits bottom pipe
            if birdBottom > bottomPipeTop {
                return true
            }
        }
        
        return false
    }
    
    private func gameOver() {
        gameState = .gameOver
        timer?.invalidate()
        
        // Update high score
        if score > highScore {
            highScore = score
            UserDefaults.standard.set(highScore, forKey: "flappyBirdHighScore")
        }
    }
    
    deinit {
        timer?.invalidate()
    }
}

#Preview {
    FlappyBirdView()
}
