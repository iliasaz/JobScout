//
//  GlassModifiers.swift
//  JobScout
//

import SwiftUI

extension View {
    @ViewBuilder
    func glassBackground(
        tint: Color? = nil,
        cornerRadius: CGFloat = 12
    ) -> some View {
        if #available(macOS 26, *) {
            let glass: Glass = if let tint {
                .regular.tint(tint)
            } else {
                .regular
            }
            self.glassEffect(glass, in: .rect(cornerRadius: cornerRadius))
        } else {
            self.background(.ultraThinMaterial, in: .rect(cornerRadius: cornerRadius))
        }
    }
}
