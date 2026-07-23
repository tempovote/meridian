import DocumentCore
import Testing
@testable import SyntaxKit

@Suite("FoldRangeAllGrammarsTests")
struct FoldRangeAllGrammarsTests {
    private func folds(_ source: String, _ languageID: String) async throws -> [FoldRange] {
        let buffer = TextBuffer(source)
        let service = SyntaxService()
        return try await service.parse(
            documentID: DocumentID(),
            languageID: languageID,
            snapshot: buffer,
            version: buffer.version,
            edit: nil,
        ).folds
    }

    @Test func bashFunctionFolds() async throws {
        let source = """
        greet() {
            echo hello
            echo world
        }
        """
        let result = try await folds(source, "bash")
        #expect(result.contains { $0.startLine == 0 && $0.endLine == 3 })
    }

    @Test func cFunctionFolds() async throws {
        let source = """
        int main(void) {
            int x = 1;
            return x;
        }
        """
        let result = try await folds(source, "c")
        #expect(result.contains { $0.startLine == 0 && $0.endLine == 3 })
    }

    @Test func cppClassFolds() async throws {
        let source = """
        class Widget {
            int value;
            void run();
        };
        """
        let result = try await folds(source, "cpp")
        #expect(result.contains { $0.startLine == 0 && $0.endLine == 3 })
    }

    @Test func cssRuleSetFolds() async throws {
        let source = """
        .box {
            color: red;
            margin: 0;
        }
        """
        let result = try await folds(source, "css")
        #expect(result.contains { $0.startLine == 0 && $0.endLine == 3 })
    }

    @Test func goFunctionFolds() async throws {
        let source = """
        func main() {
            x := 1
            fmt.Println(x)
        }
        """
        let result = try await folds(source, "go")
        #expect(result.contains { $0.startLine == 0 && $0.endLine == 3 })
    }

    @Test func htmlElementFolds() async throws {
        let source = """
        <div>
            <p>hello</p>
            <p>world</p>
        </div>
        """
        let result = try await folds(source, "html")
        #expect(result.contains { $0.startLine == 0 && $0.endLine == 3 })
    }

    @Test func javaMethodFolds() async throws {
        let source = """
        class Greeter {
            void greet() {
                System.out.println("hi");
            }
        }
        """
        let result = try await folds(source, "java")
        #expect(result.contains { $0.startLine == 0 && $0.endLine == 4 })
    }

    @Test func javascriptFunctionFolds() async throws {
        let source = """
        function greet() {
            const x = 1;
            console.log(x);
        }
        """
        let result = try await folds(source, "javascript")
        #expect(result.contains { $0.startLine == 0 && $0.endLine == 3 })
    }

    @Test func markdownSectionFolds() async throws {
        let source = """
        # Title

        Some body text
        that spans lines.
        """
        let result = try await folds(source, "markdown")
        #expect(result.contains { $0.startLine == 0 && $0.endLine == 3 })
    }

    @Test func phpFunctionFolds() async throws {
        let source = """
        <?php
        function greet() {
            $x = 1;
            echo $x;
        }
        """
        let result = try await folds(source, "php")
        #expect(result.contains { $0.startLine == 1 && $0.endLine == 4 })
    }

    @Test func rubyMethodFolds() async throws {
        let source = """
        def greet
          x = 1
          puts x
        end
        """
        let result = try await folds(source, "ruby")
        #expect(result.contains { $0.startLine == 0 && $0.endLine == 3 })
    }

    @Test func rustFunctionFolds() async throws {
        let source = """
        fn main() {
            let x = 1;
            println!("{}", x);
        }
        """
        let result = try await folds(source, "rust")
        #expect(result.contains { $0.startLine == 0 && $0.endLine == 3 })
    }

    @Test func tomlTableFolds() async throws {
        let source = """
        [package]
        name = "demo"
        version = "0.1.0"
        """
        let result = try await folds(source, "toml")
        #expect(result.contains { $0.startLine == 0 && $0.endLine == 2 })
    }

    @Test func typescriptInterfaceFolds() async throws {
        let source = """
        interface Point {
            x: number;
            y: number;
        }
        """
        let result = try await folds(source, "typescript")
        #expect(result.contains { $0.startLine == 0 && $0.endLine == 3 })
    }

    @Test func xmlElementFolds() async throws {
        let source = """
        <root>
            <child>hello</child>
            <child>world</child>
        </root>
        """
        let result = try await folds(source, "xml")
        #expect(result.contains { $0.startLine == 0 && $0.endLine == 3 })
    }

    @Test func yamlBlockMappingFolds() async throws {
        let source = """
        person:
          name: alice
          age: 30
        """
        let result = try await folds(source, "yaml")
        #expect(result.contains { $0.startLine == 0 && $0.endLine == 2 })
    }
}
