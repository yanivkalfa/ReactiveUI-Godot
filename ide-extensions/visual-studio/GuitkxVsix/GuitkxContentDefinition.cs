using System.ComponentModel.Composition;
using Microsoft.VisualStudio.LanguageServer.Client;
using Microsoft.VisualStudio.Utilities;

namespace GuitkxVsix
{
    // Defines the `guitkx` content type and maps the .guitkx file extension to it. The content type
    // derives from CodeRemoteContentDefinition so the VS LSP client (ILanguageClient) attaches to
    // .guitkx editors. Coloring is supplied by the TextMate grammar registered in guitkx.pkgdef
    // (VS never drives colorization over LSP).
    //
    // `gdscript` mirrors the VS Code extension's plain-.gd analysis (row 15 of the parity plan): the
    // same shared server already drives diagnostics/completion/hover/navigation/rename/formatting for
    // plain .gd via gdscript-analyzer, this just gives VS2022 the content type to attach to. Unlike VS
    // Code, this is unconditional today, not gated by the "Analyze plain .gd files" option -- MEF
    // ContentTypeDefinition/FileExtensionToContentTypeDefinition exports are static (reflected once at
    // catalog-build time), so there's no in-process way to withhold them based on a runtime setting
    // the way VS Code's client conditionally pushes a document selector entry at activation. Gating
    // this properly needs a small, additive server-side init-option check (mirroring VS Code's
    // enableGdscriptAnalysis exactly) -- deliberately not done in this campaign, since it touches
    // lsp-server/src/server.ts, shared with VS Code (see the parity plan's Phase 1 note on G-12 for
    // the same reasoning). Also unlike .guitkx, there is no bundled TextMate grammar for plain
    // GDScript here -- coloring relies on the analyzer's semantic tokens alone (the parity plan's
    // Phase 2 explicitly leaves this as an open choice; semantic-tokens-only was chosen to avoid
    // introducing a whole new grammar file under this campaign's scope). If another installed
    // extension (e.g. a Godot-tools-style extension) already claims a `gdscript` content type or the
    // `.gd` extension, VS merges same-named ContentTypeDefinitions and MEF ordering decides the
    // FileExtensionToContentTypeDefinition winner -- not something this project can detect or resolve
    // at build time; the "Analyze plain .gd files" option is the user's manual escape hatch (VS Code's
    // README carries the equivalent godot-tools coexistence note).
    public static class GuitkxContentDefinition
    {
        [Export]
        [Name("guitkx")]
        [BaseDefinition(CodeRemoteContentDefinition.CodeRemoteContentTypeName)]
        internal static ContentTypeDefinition GuitkxContentTypeDefinition;

        [Export]
        [FileExtension(".guitkx")]
        [ContentType("guitkx")]
        internal static FileExtensionToContentTypeDefinition GuitkxFileExtensionDefinition;

        [Export]
        [Name("gdscript")]
        [BaseDefinition(CodeRemoteContentDefinition.CodeRemoteContentTypeName)]
        internal static ContentTypeDefinition GdscriptContentTypeDefinition;

        [Export]
        [FileExtension(".gd")]
        [ContentType("gdscript")]
        internal static FileExtensionToContentTypeDefinition GdscriptFileExtensionDefinition;
    }
}
