//
//  MyAppWidgetBundle.swift
//  MyAppWidget
//
//  Created by Otis Lau on 2025-12-22.
//

import WidgetKit
import SwiftUI

@main
struct MyAppWidgetBundle: WidgetBundle {
    var body: some Widget {
        MyAppWidget()
        MyAppWidgetControl()
        MyAppWidgetLiveActivity()
    }
}
