//
//  Color.swift
//  Whisper
//
//  Created by  jwkwon0817 on 11/9/25.
//

import SwiftUI

extension Color {
    static let system = Color(light: Color("System/Black"), dark: Color("System/White"))
    static var content: ContentColors.Type { ContentColors.self }
}

enum ContentColors {
    static let primary = Color(light: Color("Grayscale/900"), dark: Color("System/White"))
    static let secondary = Color(light: Color("Grayscale/600"), dark: Color("Grayscale/400"))
    static let tertiary = Color(light: Color("Grayscale/500"), dark: Color("Grayscale/500"))
    static let disabled = Color(light: Color("Grayscale/300"), dark: Color("Grayscale/600"))
    static let inverse = Color(light: Color("System/White"), dark: Color("Grayscale/900"))
}

enum SurfaceColors {
    static let `default` = Color(light: Color("System/White"), dark: Color("Grayscale/900"))
    static let secondary = Color(light: Color("Grayscale/50"), dark: Color("Grayscale/800"))
    static let tertiary = Color(light: Color("Grayscale/100"), dark: Color("Grayscale/700"))
    static let elevated = Color(light: Color("System/White"), dark: Color("Grayscale/800"))
    static let brand = Color(light: Color("Brand/50"), dark: Color("Solid/Blue/900"))
}

enum LineColors {
    static let `default` = Color(light: Color("Grayscale/200"), dark: Color("Grayscale/700"))
    static let secondary = Color(light: Color("Grayscale/300"), dark: Color("Grayscale/800"))
    static let tertiary = Color(light: Color("Grayscale/400"), dark: Color("Grayscale/900"))
    static let brand = Color(light: Color("Brand/300"), dark: Color("Solid/Blue/700"))
    static let focus = Color(light: Color("Brand/600"), dark: Color("Solid/Blue/500"))
}

enum StatusColors {
    static let success = Color(light: Color("Solid/Green/500"), dark: Color("Solid/Green/400"))
    static let successBackground = Color(light: Color("Solid/Green/100"), dark: Color("Solid/Green/900"))
    
    static let error = Color(light: Color("Solid/Red/500"), dark: Color("Solid/Red/400"))
    static let errorBackground = Color(light: Color("Solid/Red/100"), dark: Color("Solid/Red/900"))
    
    static let warning = Color(light: Color("Solid/Yellow/500"), dark: Color("Solid/Yellow/400"))
    static let warningBackground = Color(light: Color("Solid/Yellow/100"), dark: Color("Solid/Yellow/900"))
    
    static let info = Color(light: Color("Solid/Blue/500"), dark: Color("Solid/Blue/400"))
    static let infoBackground = Color(light: Color("Solid/Blue/100"), dark: Color("Solid/Blue/900"))
}
