using System.ComponentModel.Composition;
using Microsoft.VisualStudio.Text.Editor;
using Microsoft.VisualStudio.Utilities;

namespace GuitkxVsix
{
    // Editor defaults for .guitkx (row 18 of the parity plan; G-19) -- the formatter's canonical
    // output is spaces at width 2 (guitkx_formatter.gd / formatGuitkx.ts DEFAULTS, "Phase D:
    // Unity-exact"); VS Code's `configurationDefaults` pins the same. Typing defaults must match
    // that canon, or every format-on-save churns the whole file's indentation. VS has no
    // `detectIndentation` to disable; there's nothing else to mirror.
    [Export(typeof(IWpfTextViewCreationListener))]
    [ContentType("guitkx")]
    [TextViewRole(PredefinedTextViewRoles.Document)]
    internal sealed class GuitkxEditorDefaults : IWpfTextViewCreationListener
    {
        public void TextViewCreated(IWpfTextView textView)
        {
            var options = textView.Options;
            options.SetOptionValue(DefaultOptions.ConvertTabsToSpacesOptionId, true);
            options.SetOptionValue(DefaultOptions.TabSizeOptionId, 2);
            options.SetOptionValue(DefaultOptions.IndentSizeOptionId, 2);
        }
    }
}
