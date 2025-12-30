//
//  JobScoutApp.swift
//  JobScout
//
//  Created by Ilia Sazonov on 12/26/25.
//

import SwiftUI

@main
struct JobScoutApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        #if os(macOS)
        Settings {
            SettingsView()
        }
        #endif
    }
}
