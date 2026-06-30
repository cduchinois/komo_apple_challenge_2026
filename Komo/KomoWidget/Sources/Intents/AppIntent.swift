//
//  AppIntent.swift
//  KomoWidget
//
//  Created by Sacha Morin on 25/06/2026.
//

import WidgetKit
import AppIntents

struct ConfigurationAppIntent: WidgetConfigurationIntent {
    static var title: LocalizedStringResource { "Komo Settings" }
    static var description: IntentDescription { "Configure your Komo Avatar." }
}
