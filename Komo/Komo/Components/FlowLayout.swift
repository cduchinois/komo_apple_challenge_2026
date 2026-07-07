//  FlowLayout.swift
//  Komo
//
//  A simple wrapping layout (used for the drains / restores pill clusters), so
//  chips flow onto new lines and stay centered like the prototype's flex-wrap.

import SwiftUI

struct FlowLayout: Layout {
    var spacing: CGFloat = 10
    var alignment: HorizontalAlignment = .center

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout Void) -> CGSize {
        let maxWidth = proposal.width ?? .infinity
        let rows = computeRows(maxWidth: maxWidth, subviews: subviews)
        let height = rows.reduce(0) { $0 + $1.height } + spacing * CGFloat(max(0, rows.count - 1))
        return CGSize(width: maxWidth == .infinity ? rows.map(\.width).max() ?? 0 : maxWidth, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout Void) {
        let rows = computeRows(maxWidth: bounds.width, subviews: subviews)
        var y = bounds.minY
        for row in rows {
            let rowWidth = row.width
            var x: CGFloat
            switch alignment {
            case .leading:  x = bounds.minX
            case .trailing: x = bounds.maxX - rowWidth
            default:        x = bounds.minX + (bounds.width - rowWidth) / 2
            }
            for item in row.items {
                let size = subviews[item.index].sizeThatFits(.unspecified)
                subviews[item.index].place(
                    at: CGPoint(x: x, y: y + (row.height - size.height) / 2),
                    proposal: ProposedViewSize(size))
                x += size.width + spacing
            }
            y += row.height + spacing
        }
    }

    private struct RowItem { let index: Int; let width: CGFloat }
    private struct Row { var items: [RowItem] = []; var width: CGFloat = 0; var height: CGFloat = 0 }

    private func computeRows(maxWidth: CGFloat, subviews: Subviews) -> [Row] {
        var rows: [Row] = []
        var current = Row()
        for (i, sub) in subviews.enumerated() {
            let size = sub.sizeThatFits(.unspecified)
            let projected = current.items.isEmpty ? size.width : current.width + spacing + size.width
            if projected > maxWidth, !current.items.isEmpty {
                rows.append(current)
                current = Row()
                current.items = [RowItem(index: i, width: size.width)]
                current.width = size.width
                current.height = size.height
            } else {
                current.width = projected
                current.items.append(RowItem(index: i, width: size.width))
                current.height = max(current.height, size.height)
            }
        }
        if !current.items.isEmpty { rows.append(current) }
        return rows
    }
}
