import Testing
@testable import openOwl

@Suite("nilIfEmpty")
struct NilIfEmptyTests {

    @Test func nil_returnsNil() {
        let value: String? = nil
        #expect(value.nilIfEmpty == nil)
    }

    @Test func empty_returnsNil() {
        let value: String? = ""
        #expect(value.nilIfEmpty == nil)
    }

    @Test func nonEmpty_returnsSelf() {
        let value: String? = "hello"
        #expect(value.nilIfEmpty == "hello")
    }

    @Test func whitespace_isNotEmpty() {
        let value: String? = "  "
        #expect(value.nilIfEmpty == "  ")
    }
}
