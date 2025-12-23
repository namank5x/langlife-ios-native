import SwiftUI

struct TagFlowLayout: Layout {
    var spacing: CGFloat = 12
    var rowSpacing: CGFloat = 12

    func sizeThatFits(
        proposal: ProposedViewSize,
        subviews: Subviews,
        cache: inout ()
    ) -> CGSize {
        let maxWidth = proposal.width ?? .infinity
        var rowWidth: CGFloat = 0
        var rowHeight: CGFloat = 0
        var totalHeight: CGFloat = 0
        var maxLineWidth: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(ProposedViewSize(width: maxWidth, height: nil))
            let itemWidth = min(size.width, maxWidth)

            if rowWidth > 0, rowWidth + spacing + itemWidth > maxWidth {
                totalHeight += rowHeight + rowSpacing
                maxLineWidth = max(maxLineWidth, rowWidth)
                rowWidth = itemWidth
                rowHeight = size.height
            } else {
                rowWidth = rowWidth == 0 ? itemWidth : rowWidth + spacing + itemWidth
                rowHeight = max(rowHeight, size.height)
            }
        }

        totalHeight += rowHeight
        maxLineWidth = max(maxLineWidth, rowWidth)

        let finalWidth = proposal.width ?? maxLineWidth
        return CGSize(width: finalWidth, height: totalHeight)
    }

    func placeSubviews(
        in bounds: CGRect,
        proposal: ProposedViewSize,
        subviews: Subviews,
        cache: inout ()
    ) {
        let maxWidth = bounds.width
        var x = bounds.minX
        var y = bounds.minY
        var rowHeight: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(ProposedViewSize(width: maxWidth, height: nil))
            let itemWidth = min(size.width, maxWidth)

            if x > bounds.minX, x + itemWidth > bounds.maxX {
                x = bounds.minX
                y += rowHeight + rowSpacing
                rowHeight = 0
            }

            subview.place(
                at: CGPoint(x: x, y: y),
                anchor: .topLeading,
                proposal: ProposedViewSize(width: itemWidth, height: size.height)
            )

            x += itemWidth + spacing
            rowHeight = max(rowHeight, size.height)
        }
    }
}
