//
//  KadenceApp.swift
//  Kadence
//
//  Created by Parsa Jalali on 09.09.26.
//

import SwiftUI
import CoreData

@main
struct KadenceApp: App {
    let persistenceController = PersistenceController.shared

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(\.managedObjectContext, persistenceController.container.viewContext)
        }
    }
}
