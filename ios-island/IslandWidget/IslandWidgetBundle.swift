//
//  IslandWidgetBundle.swift
//  IslandWidget
//
//  Created by MichaeGaol on 2026/6/23.
//

import WidgetKit
import SwiftUI

@main
struct IslandWidgetBundle: WidgetBundle {
    var body: some Widget {
        IslandWidget()
        IslandWidgetControl()
        IslandWidgetLiveActivity()
    }
}
