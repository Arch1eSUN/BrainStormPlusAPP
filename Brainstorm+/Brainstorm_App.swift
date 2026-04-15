//
//  Brainstorm_App.swift
//  Brainstorm+
//
//  Created by Archie Sun on 4/14/26.
//

import SwiftUI
import SwiftData

// @main
struct Brainstorm_App: App {
    @State private var sessionManager = SessionManager()

    var sharedModelContainer: ModelContainer = {
        let schema = Schema([
            Item.self,
        ])
        let modelConfiguration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)

        do {
            return try ModelContainer(for: schema, configurations: [modelConfiguration])
        } catch {
            fatalError("Could not create ModelContainer: \(error)")
        }
    }()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(sessionManager)
        }
        .modelContainer(sharedModelContainer)
    }
}
