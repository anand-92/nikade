import Testing
import Foundation
import SwiftUI
@testable import openOwl

@Suite("FileIcons")
struct FileIconsTests {

    // MARK: - iconName

    @Test func iconName_swift() {
        let url = URL(fileURLWithPath: "/test/App.swift")
        #expect(FileIcons.iconName(for: url) == "swift")
    }

    @Test func iconName_markdown() {
        for ext in ["md", "txt", "log"] {
            let url = URL(fileURLWithPath: "/test/file.\(ext)")
            #expect(FileIcons.iconName(for: url) == "doc.text")
        }
    }

    @Test func iconName_config() {
        for ext in ["json", "yml", "yaml", "toml", "plist"] {
            let url = URL(fileURLWithPath: "/test/file.\(ext)")
            #expect(FileIcons.iconName(for: url) == "curlybraces")
        }
    }

    @Test func iconName_image() {
        for ext in ["png", "jpg", "jpeg", "gif", "webp", "svg"] {
            let url = URL(fileURLWithPath: "/test/file.\(ext)")
            #expect(FileIcons.iconName(for: url) == "photo")
        }
    }

    @Test func iconName_shell() {
        for ext in ["sh", "zsh", "bash"] {
            let url = URL(fileURLWithPath: "/test/file.\(ext)")
            #expect(FileIcons.iconName(for: url) == "terminal")
        }
    }

    @Test func iconName_javascript() {
        for ext in ["js", "ts", "tsx", "jsx"] {
            let url = URL(fileURLWithPath: "/test/file.\(ext)")
            #expect(FileIcons.iconName(for: url) == "chevron.left.forwardslash.chevron.right")
        }
    }

    @Test func iconName_unknown_fallsBackToDoc() {
        let url = URL(fileURLWithPath: "/test/file.xyz")
        #expect(FileIcons.iconName(for: url) == "doc")
    }

    @Test func iconName_noExtension_fallsBackToDoc() {
        let url = URL(fileURLWithPath: "/test/Makefile")
        #expect(FileIcons.iconName(for: url) == "doc")
    }

    @Test func iconName_caseInsensitive() {
        let url = URL(fileURLWithPath: "/test/App.SWIFT")
        #expect(FileIcons.iconName(for: url) == "swift")
    }

    // MARK: - iconColor

    @Test func iconColor_swift_isOrange() {
        let url = URL(fileURLWithPath: "/test/App.swift")
        #expect(FileIcons.iconColor(for: url) == Color(nsColor: .systemOrange))
    }

    @Test func iconColor_javascript_isYellow() {
        for ext in ["js", "ts", "tsx", "jsx"] {
            let url = URL(fileURLWithPath: "/test/file.\(ext)")
            #expect(FileIcons.iconColor(for: url) == Color(nsColor: .systemYellow))
        }
    }

    @Test func iconColor_python_isGreen() {
        let url = URL(fileURLWithPath: "/test/main.py")
        #expect(FileIcons.iconColor(for: url) == Color(nsColor: .systemGreen))
    }

    @Test func iconColor_config_isPurple() {
        for ext in ["json", "yml", "yaml"] {
            let url = URL(fileURLWithPath: "/test/file.\(ext)")
            #expect(FileIcons.iconColor(for: url) == Color(nsColor: .systemPurple))
        }
    }

    @Test func iconColor_unknown_isSecondary() {
        let url = URL(fileURLWithPath: "/test/file.xyz")
        #expect(FileIcons.iconColor(for: url) == .secondary)
    }
}
