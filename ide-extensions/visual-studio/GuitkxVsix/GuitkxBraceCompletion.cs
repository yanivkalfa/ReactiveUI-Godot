using System.ComponentModel.Composition;
using Microsoft.VisualStudio.Text.BraceCompletion;
using Microsoft.VisualStudio.Utilities;

namespace GuitkxVsix
{
    // Auto-close brace/quote pairs for .guitkx (row 19 of the parity plan) -- matches VS Code's
    // language-configuration.json brackets/autoClosingPairs list: markup tags (<>), JSX-style
    // expression braces, GDScript's usual (), [], and both quote styles.
    [Export(typeof(IBraceCompletionDefaultProvider))]
    [ContentType("guitkx")]
    [BracePair('{', '}')]
    [BracePair('(', ')')]
    [BracePair('[', ']')]
    [BracePair('<', '>')]
    [BracePair('"', '"')]
    [BracePair('\'', '\'')]
    internal sealed class GuitkxBraceCompletion : IBraceCompletionDefaultProvider
    {
    }
}
