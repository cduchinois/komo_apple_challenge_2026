//
//  KomoWidgetBundle.swift
//  KomoWidget
//
//  Created by Sacha Morin on 25/06/2026.
//

import WidgetKit
import SwiftUI

@main
struct KomoWidgetBundle: WidgetBundle {
    var body: some Widget {
        KomoWidget()
        KomoWidgetControl()
        KomoWidgetLiveActivity()
    }
}
