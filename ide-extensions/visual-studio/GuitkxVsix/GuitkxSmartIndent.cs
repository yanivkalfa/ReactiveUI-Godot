using System.ComponentModel.Composition;
using System.Text.RegularExpressions;
using Microsoft.VisualStudio.Text;
using Microsoft.VisualStudio.Text.Editor;
using Microsoft.VisualStudio.Utilities;

namespace GuitkxVsix
{
    // Smart indent for .guitkx (row 21 of the parity plan) -- a minimal port of the two
    // indentationRules regexes from ide-extensions/vscode/language-configuration.json (kept
    // byte-for-byte identical to that source so the two never drift):
    //   increaseIndentPattern: "(\{[^}\"']*$)|(\([^)\"']*$)|(:\s*$)|(^(?!\s*</).*[^/]>\s*$)|(<[A-Za-z][^>]*$)"
    //   decreaseIndentPattern: "^\s*(\}|\)|</)"
    // The "Enter between `></` splits into an indented middle line" onEnterRule from that same file
    // is deliberately NOT ported here (the plan marks it optional; it needs a command filter on
    // RETURN, a different mechanism entirely -- ship the basic indent first).
    [Export(typeof(ISmartIndentProvider))]
    [ContentType("guitkx")]
    internal sealed class GuitkxSmartIndentProvider : ISmartIndentProvider
    {
        public ISmartIndent CreateSmartIndent(ITextView textView) => new GuitkxSmartIndent(textView);
    }

    internal sealed class GuitkxSmartIndent : ISmartIndent
    {
        // Mirrors language-configuration.json's increaseIndentPattern verbatim (RegexOptions.None to
        // match VS Code's non-multiline, non-dotall JS regex semantics -- $ anchors end-of-string here
        // since we always test a single line's text, not the whole buffer).
        private static readonly Regex IncreaseIndentPattern = new Regex(
            @"(\{[^}""']*$)|(\([^)""']*$)|(:\s*$)|(^(?!\s*</).*[^/]>\s*$)|(<[A-Za-z][^>]*$)",
            RegexOptions.Compiled);

        private static readonly Regex DecreaseIndentPattern = new Regex(
            @"^\s*(\}|\)|</)",
            RegexOptions.Compiled);

        private readonly ITextView _textView;

        public GuitkxSmartIndent(ITextView textView)
        {
            _textView = textView;
        }

        public int? GetDesiredIndentation(ITextSnapshotLine line)
        {
            var tabSize = _textView.Options.GetOptionValue(DefaultOptions.TabSizeOptionId);
            var snapshot = line.Snapshot;
            var lineNumber = line.LineNumber;

            // Walk up to the nearest non-blank previous line -- an Enter on a blank line shouldn't
            // reset indentation to zero.
            var previousLineNumber = lineNumber - 1;
            while (previousLineNumber >= 0 && snapshot.GetLineFromLineNumber(previousLineNumber).GetText().Trim().Length == 0)
                previousLineNumber--;

            if (previousLineNumber < 0)
                return 0;

            var previousLine = snapshot.GetLineFromLineNumber(previousLineNumber);
            var previousText = previousLine.GetText();
            var previousIndent = GetIndentColumn(previousText, tabSize);

            var indent = previousIndent;
            if (IncreaseIndentPattern.IsMatch(previousText))
                indent += tabSize;

            // The line being indented may already have (partial) text typed on it (e.g. reformatting,
            // not just a fresh Enter) -- if IT looks like a closer, pull the computed indent back in.
            if (DecreaseIndentPattern.IsMatch(line.GetText()))
                indent -= tabSize;

            return indent < 0 ? 0 : indent;
        }

        private static int GetIndentColumn(string lineText, int tabSize)
        {
            var column = 0;
            foreach (var ch in lineText)
            {
                if (ch == ' ')
                    column++;
                else if (ch == '\t')
                    column += tabSize - (column % tabSize);
                else
                    break;
            }
            return column;
        }

        public void Dispose()
        {
        }
    }
}
