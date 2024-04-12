//
//  Markdown.swift
//  
//
//  Created by John Biggs on 19.02.24.
//

import Foundation
import Markdown

struct MarkdownToHTML: MarkupVisitor {
    mutating func recurseInto(_ markup: Markup, separator: String = "") -> String {
        markup.children.enumerated().reduce(into: "") { partialResult, item in
            let (index, child) = item
            let isLast = index == (markup.childCount - 1)
            partialResult += visit(child) + (isLast ? "" : separator)
        }
    }

    mutating func defaultVisit(_ markup: Markup) -> String {
        return recurseInto(markup)
    }

    func visitText(_ text: Text) -> String {
        text.plainText
    }

    mutating func visitStrong(_ strong: Strong) -> String {
        return "<strong>\(recurseInto(strong))</strong>"
    }

    mutating func visitEmphasis(_ emphasis: Emphasis) -> String {
        "<em>\(recurseInto(emphasis))</em>"
    }

    mutating func visitStrikethrough(_ strikethrough: Strikethrough) -> String {
        "<s>\(recurseInto(strikethrough))</s>"
    }

    mutating func visitParagraph(_ paragraph: Paragraph) -> String {
        "<p>\(recurseInto(paragraph))</p>"
    }

    mutating func visitBlockQuote(_ blockQuote: BlockQuote) -> String {
        """
        <blockquote>
        \(recurseInto(blockQuote, separator: "\n").indented())
        </blockquote>
        """
    }

    mutating func visitCodeBlock(_ codeBlock: CodeBlock) -> String {
        var attributes = ""
        if let language = codeBlock.language {
            attributes += " class='language-\(language)' "
        }
        return """
            <pre><code\(attributes)>
            \(recurseInto(codeBlock))
            </code></pre>
            """
    }

    mutating func visitInlineCode(_ inlineCode: InlineCode) -> String {
        "<code>\(recurseInto(inlineCode))</code>"
    }

    mutating func visitLink(_ link: Link) -> String {
        guard let dest = link.destination else {
            return recurseInto(link)
        }

        return "<a href='\(dest)'>\(recurseInto(link))</a>"
    }

    mutating func visitUnorderedList(_ unorderedList: UnorderedList) -> String {
        return """
            <ul>
            \(recurseInto(unorderedList, separator: "\n").indented())
            </ul>
            """
    }

    mutating func visitOrderedList(_ orderedList: OrderedList) -> String {
        return """
            <ol>
            \(recurseInto(orderedList, separator: "\n").indented())
            </ol>
            """
    }

    mutating func visitListItem(_ listItem: ListItem) -> String {
        "<li>\(recurseInto(listItem))</li>"
    }

    mutating func visitHeading(_ heading: Heading) -> String {
        let tag = "h\(heading.level)"
        return "<\(tag)>\(recurseInto(heading))</\(tag)>"
    }

    mutating func visitHTMLBlock(_ html: HTMLBlock) -> String {
        return html.rawHTML
    }

    mutating func visitLineBreak(_ lineBreak: LineBreak) -> String {
        return "<br />"
    }

    mutating func visitImage(_ image: Image) -> String {
        var extras = ""
        if let title = image.title {
            extras += "title='\(title)'"
        }

        return "<img src='\(image.source ?? "")' \(extras) />"
    }

    mutating func visitTable(_ table: Table) -> String {
        return """
        <table>
        \(recurseInto(table, separator: "\n").indented())
        </table>
        """
    }

    mutating func visitTableHead(_ tableHead: Table.Head) -> String {
        return """
        <thead>
        \(recurseInto(tableHead, separator: "\n").indented())
        </thead>
        """
    }

    mutating func visitTableBody(_ tableBody: Table.Body) -> String {
        return """
        <tbody>
        \(recurseInto(tableBody, separator: "\n").indented())
        </tbody>
        """
    }

    mutating func visitTableRow(_ tableRow: Table.Row) -> String {
        return """
        <tr>
        \(recurseInto(tableRow, separator: "\n").indented())
        </tr>
        """
    }

    mutating func visitTableCell(_ tableCell: Table.Cell) -> String {
        "<td>\(recurseInto(tableCell))</td>"
    }
}
