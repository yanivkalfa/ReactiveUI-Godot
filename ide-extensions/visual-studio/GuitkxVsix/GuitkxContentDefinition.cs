using System.ComponentModel.Composition;
using Microsoft.VisualStudio.LanguageServer.Client;
using Microsoft.VisualStudio.Utilities;

namespace GuitkxVsix
{
    // Defines the `guitkx` content type and maps the .guitkx file extension to it. The content type
    // derives from CodeRemoteContentDefinition so the VS LSP client (ILanguageClient) attaches to
    // .guitkx editors. Coloring is supplied by the TextMate grammar registered in guitkx.pkgdef
    // (VS never drives colorization over LSP).
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
    }
}
