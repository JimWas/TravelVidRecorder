import SwiftUI

// MARK: - Tetris Piece
struct TetrisPiece {
    var shape: [[Bool]]
    var color: Color
    var x: Int
    var y: Int
    
    static let shapes: [[[Bool]]] = [
        // I
        [[true, true, true, true]],
        // O
        [[true, true],
         [true, true]],
        // T
        [[false, true, false],
         [true, true, true]],
        // S
        [[false, true, true],
         [true, true, false]],
        // Z
        [[true, true, false],
         [false, true, true]],
        // J
        [[true, false, false],
         [true, true, true]],
        // L
        [[false, false, true],
         [true, true, true]]
    ]
    
    static let colors: [Color] = [.cyan, .yellow, .purple, .green, .red, .blue, .orange]
    
    static func random() -> TetrisPiece {
        let index = Int.random(in: 0..<shapes.count)
        return TetrisPiece(
            shape: shapes[index],
            color: colors[index],
            x: 3,
            y: 0
        )
    }
    
    func rotated() -> TetrisPiece {
        let rows = shape.count
        let cols = shape[0].count
        var newShape = Array(repeating: Array(repeating: false, count: rows), count: cols)
        
        for r in 0..<rows {
            for c in 0..<cols {
                newShape[c][rows - 1 - r] = shape[r][c]
            }
        }
        
        return TetrisPiece(shape: newShape, color: color, x: x, y: y)
    }
}

// MARK: - Tetris Game View
struct TetrisGameView: View {
    @StateObject private var game = TetrisGameModel()
    
    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            
            VStack(spacing: 0) {
                // Score - Fixed padding for safe area
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Score")
                            .font(.caption)
                            .foregroundColor(.gray)
                        Text("\(game.score)")
                            .font(.title3.bold())
                            .foregroundColor(.white)
                    }
                    
                    Spacer()
                    
                    // Pause Button
                    Button(action: { game.togglePause() }) {
                        Image(systemName: game.isPaused ? "play.fill" : "pause.fill")
                            .font(.title2)
                            .foregroundColor(.white)
                            .frame(width: 44, height: 44)
                            .background(Color.blue.opacity(0.8))
                            .cornerRadius(8)
                    }
                    
                    Spacer()
                    
                    VStack(alignment: .trailing, spacing: 4) {
                        Text("Level")
                            .font(.caption)
                            .foregroundColor(.gray)
                        Text("\(game.level)")
                            .font(.title3.bold())
                            .foregroundColor(.white)
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 50) // Safe area padding
                .padding(.bottom, 10)
                
                // Game Board
                gameBoard
                    .padding(.horizontal, 10)
                
                Spacer(minLength: 20)
                
                // Controls
                VStack(spacing: 15) {
                    HStack(spacing: 20) {
                        // Rotate
                        Button(action: { game.rotate() }) {
                            Image(systemName: "arrow.clockwise")
                                .font(.title2)
                                .frame(width: 70, height: 70)
                                .background(Color.blue)
                                .foregroundColor(.white)
                                .cornerRadius(12)
                        }
                        
                        // Drop
                        Button(action: { game.hardDrop() }) {
                            VStack(spacing: 4) {
                                Image(systemName: "arrow.down.to.line")
                                    .font(.title2)
                                Text("Drop")
                                    .font(.caption)
                            }
                            .frame(width: 70, height: 70)
                            .background(Color.orange)
                            .foregroundColor(.white)
                            .cornerRadius(12)
                        }
                    }
                    
                    HStack(spacing: 20) {
                        // Left
                        Button(action: { game.moveLeft() }) {
                            Image(systemName: "arrow.left")
                                .font(.title2)
                                .frame(width: 70, height: 70)
                                .background(Color.blue)
                                .foregroundColor(.white)
                                .cornerRadius(12)
                        }
                        
                        // Down
                        Button(action: { game.moveDown() }) {
                            Image(systemName: "arrow.down")
                                .font(.title2)
                                .frame(width: 70, height: 70)
                                .background(Color.blue)
                                .foregroundColor(.white)
                                .cornerRadius(12)
                        }
                        
                        // Right
                        Button(action: { game.moveRight() }) {
                            Image(systemName: "arrow.right")
                                .font(.title2)
                                .frame(width: 70, height: 70)
                                .background(Color.blue)
                                .foregroundColor(.white)
                                .cornerRadius(12)
                        }
                    }
                }
                .padding(.bottom, 40)
            }
            
            // Game Over overlay
            if game.isGameOver {
                Color.black.opacity(0.8)
                    .ignoresSafeArea()
                
                VStack(spacing: 20) {
                    Text("Game Over!")
                        .font(.largeTitle.bold())
                        .foregroundColor(.white)
                    
                    Text("Score: \(game.score)")
                        .font(.title2)
                        .foregroundColor(.white)
                    
                    Button("Play Again") {
                        game.reset()
                    }
                    .padding(.horizontal, 40)
                    .padding(.vertical, 15)
                    .background(Color.blue)
                    .foregroundColor(.white)
                    .cornerRadius(10)
                }
            }
            
            // Paused overlay
            if game.isPaused && !game.isGameOver {
                Color.black.opacity(0.7)
                    .ignoresSafeArea()
                
                VStack(spacing: 20) {
                    Text("PAUSED")
                        .font(.largeTitle.bold())
                        .foregroundColor(.white)
                    
                    Button(action: { game.togglePause() }) {
                        HStack(spacing: 8) {
                            Image(systemName: "play.fill")
                            Text("Resume")
                        }
                        .padding(.horizontal, 40)
                        .padding(.vertical, 15)
                        .background(Color.green)
                        .foregroundColor(.white)
                        .cornerRadius(10)
                        .font(.title3)
                    }
                }
            }
        }
        .onAppear {
            game.start()
        }
    }
    
    // MARK: - Game Board View
    private var gameBoard: some View {
        GeometryReader { geo in
            let boardWidth = min(geo.size.width, 300)
            let cellSize = boardWidth / CGFloat(game.cols)
            let boardHeight = cellSize * CGFloat(game.rows)
            
            ZStack(alignment: .topLeading) {
                // Background grid
                VStack(spacing: 0) {
                    ForEach(0..<game.rows, id: \.self) { row in
                        HStack(spacing: 0) {
                            ForEach(0..<game.cols, id: \.self) { col in
                                Rectangle()
                                    .fill(game.board[row][col] ?? Color.gray.opacity(0.1))
                                    .frame(width: cellSize, height: cellSize)
                                    .border(Color.gray.opacity(0.3), width: 0.5)
                            }
                        }
                    }
                }
                .frame(width: boardWidth, height: boardHeight)
                
                // Current piece - properly aligned to grid
                if let piece = game.currentPiece {
                    ForEach(0..<piece.shape.count, id: \.self) { r in
                        ForEach(0..<piece.shape[r].count, id: \.self) { c in
                            if piece.shape[r][c] {
                                Rectangle()
                                    .fill(piece.color)
                                    .frame(width: cellSize, height: cellSize)
                                    .border(Color.black, width: 1)
                                    .position(
                                        x: CGFloat(piece.x + c) * cellSize + cellSize / 2,
                                        y: CGFloat(piece.y + r) * cellSize + cellSize / 2
                                    )
                            }
                        }
                    }
                }
            }
            .frame(width: boardWidth, height: boardHeight)
            .position(x: geo.size.width / 2, y: geo.size.height / 2)
        }
    }
}

// MARK: - Tetris Game Model
@MainActor
class TetrisGameModel: ObservableObject {
    @Published var board: [[Color?]] = []
    @Published var currentPiece: TetrisPiece?
    @Published var score = 0
    @Published var level = 1
    @Published var isGameOver = false
    @Published var isPaused = false
    
    let rows = 20
    let cols = 10
    private var timer: Timer?
    private var dropInterval: TimeInterval = 1.0
    
    init() {
        reset()
    }
    
    func start() {
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: dropInterval, repeats: true) { [weak self] _ in
            guard let self = self else { return }
            Task { @MainActor in
                self.tick()
            }
        }
    }
    
    func reset() {
        board = Array(repeating: Array(repeating: nil, count: cols), count: rows)
        currentPiece = TetrisPiece.random()
        score = 0
        level = 1
        isGameOver = false
        isPaused = false
        dropInterval = 1.0
        start()
    }
    
    func togglePause() {
        isPaused.toggle()
        
        if isPaused {
            timer?.invalidate()
            timer = nil
        } else {
            start()
        }
    }
    
    private func tick() {
        guard !isGameOver, !isPaused else { return }
        
        if !moveDown() {
            lockPiece()
            clearLines()
            spawnNewPiece()
        }
    }
    
    func moveLeft() {
        guard !isPaused, !isGameOver else { return }
        guard var piece = currentPiece else { return }
        piece.x -= 1
        if isValidPosition(piece) {
            currentPiece = piece
        }
    }
    
    func moveRight() {
        guard !isPaused, !isGameOver else { return }
        guard var piece = currentPiece else { return }
        piece.x += 1
        if isValidPosition(piece) {
            currentPiece = piece
        }
    }
    
    @discardableResult
    func moveDown() -> Bool {
        guard !isPaused, !isGameOver else { return false }
        guard var piece = currentPiece else { return false }
        piece.y += 1
        if isValidPosition(piece) {
            currentPiece = piece
            return true
        }
        return false
    }
    
    func hardDrop() {
        guard !isPaused, !isGameOver else { return }
        guard var piece = currentPiece else { return }
        var dropDistance = 0
        
        // Keep moving down until we hit something
        while true {
            piece.y += 1
            if isValidPosition(piece) {
                dropDistance += 1
                currentPiece = piece
            } else {
                break
            }
        }
        
        // Add bonus points for hard drop (capped to prevent overflow)
        score += min(dropDistance * 2, 1000)
        
        // Lock the piece immediately
        lockPiece()
        clearLines()
        spawnNewPiece()
    }
    
    func rotate() {
        guard !isPaused, !isGameOver else { return }
        guard let piece = currentPiece else { return }
        let rotated = piece.rotated()
        
        // Try normal rotation
        if isValidPosition(rotated) {
            currentPiece = rotated
            return
        }
        
        // Try wall kick (move left/right if rotation doesn't fit)
        for offset in [-1, 1, -2, 2] {
            var adjusted = rotated
            adjusted.x += offset
            if isValidPosition(adjusted) {
                currentPiece = adjusted
                return
            }
        }
    }
    
    private func isValidPosition(_ piece: TetrisPiece) -> Bool {
        for r in 0..<piece.shape.count {
            for c in 0..<piece.shape[r].count {
                if piece.shape[r][c] {
                    let boardX = piece.x + c
                    let boardY = piece.y + r
                    
                    // Check boundaries
                    if boardX < 0 || boardX >= cols || boardY >= rows {
                        return false
                    }
                    
                    // Check collision with existing pieces
                    if boardY >= 0 && board[boardY][boardX] != nil {
                        return false
                    }
                }
            }
        }
        return true
    }
    
    private func lockPiece() {
        guard let piece = currentPiece else { return }
        
        for r in 0..<piece.shape.count {
            for c in 0..<piece.shape[r].count {
                if piece.shape[r][c] {
                    let boardX = piece.x + c
                    let boardY = piece.y + r
                    
                    if boardY >= 0 && boardY < rows && boardX >= 0 && boardX < cols {
                        board[boardY][boardX] = piece.color
                    }
                }
            }
        }
    }
    
    private func clearLines() {
        var linesCleared = 0
        
        var row = rows - 1
        while row >= 0 {
            if board[row].allSatisfy({ $0 != nil }) {
                board.remove(at: row)
                board.insert(Array(repeating: nil, count: cols), at: 0)
                linesCleared += 1
                // Don't decrement row, check same position again
            } else {
                row -= 1
            }
        }
        
        if linesCleared > 0 {
            // Scoring: 1 line = 100, 2 lines = 300, 3 lines = 500, 4 lines = 800
            let baseScore = [0, 100, 300, 500, 800]
            let lineScore = baseScore[min(linesCleared, 4)] * level
            score = min(score + lineScore, 999999) // Cap score to prevent overflow
            
            // Increase level every 1000 points
            let newLevel = min((score / 1000) + 1, 50) // Cap level at 50
            if newLevel > level {
                level = newLevel
                dropInterval = max(0.1, 1.0 - Double(level - 1) * 0.08)
                start() // Restart timer with new interval
            }
        }
    }
    
    private func spawnNewPiece() {
        currentPiece = TetrisPiece.random()
        
        if let piece = currentPiece, !isValidPosition(piece) {
            isGameOver = true
            timer?.invalidate()
        }
    }
    
    deinit {
        timer?.invalidate()
    }
}
