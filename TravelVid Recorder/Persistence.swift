//
//  Persistence.swift
//  TravelVid Recorder
//
//  Created by Jim Washkau on 10/29/25.
//

import CoreData
import os

struct PersistenceController {
    static let shared = PersistenceController()
    private static let logger = Logger(subsystem: "TravelVidRecorder", category: "Persistence")

    let container: NSPersistentContainer

    init(inMemory: Bool = false) {
        // Make sure this matches your .xcdatamodeld file name exactly
        container = NSPersistentContainer(name: "TravelVid_Recorder")

        if inMemory {
            container.persistentStoreDescriptions.first?.url = URL(fileURLWithPath: "/dev/null")
        }

        container.loadPersistentStores { storeDescription, error in
            if let error = error as NSError? {
                #if DEBUG
                fatalError("Unresolved error \(error), \(error.userInfo)")
                #else
                Self.logger.error("Core Data load error: \(error.localizedDescription)")
                #endif
            } else {
                Self.logger.info("Core Data store loaded: \(storeDescription.url?.absoluteString ?? "unknown URL")")
            }
        }

        // Merge background saves into main context automatically
        container.viewContext.automaticallyMergesChangesFromParent = true
    }

    // MARK: - Preview Support
    @MainActor
    static let preview: PersistenceController = {
        let result = PersistenceController(inMemory: true)
        let viewContext = result.container.viewContext
        // Create mock data here if needed
        return result
    }()

    // MARK: - Helpers
    func saveContext() {
        let context = container.viewContext
        if context.hasChanges {
            do {
                try context.save()
            } catch {
                let nsError = error as NSError
                Self.logger.error("Failed to save context: \(nsError.localizedDescription)")
            }
        }
    }

    func newBackgroundContext() -> NSManagedObjectContext {
        let context = container.newBackgroundContext()
        context.mergePolicy = NSMergeByPropertyObjectTrumpMergePolicy
        return context
    }
}
