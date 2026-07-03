//
//  PalworldApp.swift
//  Palworld
//
//  Created by Pedro Saldanha on 03/07/2026.
//

import SwiftUI
import SwiftData

@main
struct PalworldApp: App {
    var body: some Scene {
        WindowGroup {
            AppRoot()
        }
        .modelContainer(for: [
            PlayerProfile.self, FacetProgress.self, CategoryXP.self,
            MissRecord.self, QuizSession.self, ActiveQuiz.self,
            AchievementState.self,
        ])
    }
}
