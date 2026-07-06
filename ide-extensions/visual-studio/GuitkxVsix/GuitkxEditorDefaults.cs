using System.ComponentModel.Composition;
using Microsoft.VisualStudio.Text.Editor;
using Microsoft.VisualStudio.Utilities;

namespace GuitkxVsix
{
    // Editor defaults for .guitkx (row 18 of the parity plan) -- VS Code's `configurationDefaults`
    // pins `.guitkx` to tabs, size 4 (the embedded GDScript requires tabs, and the compiler emits
    // tabs). VS has no `detectIndentation` to disable; there's nothing else to mirror.
    [Export(typeof(IWpfTextViewCreationListener))]
    [ContentType("guitkx")]
    [TextViewRole(PredefinedTextViewRoles.Document)]
    internal sealed class GuitkxEditorDefaults : IWpfTextViewCreationListener
    {
        public void TextViewCreated(IWpfTextView textView)
        {
            var options = textView.Options;
            options.SetOptionValue(DefaultOptions.ConvertTabsToSpacesOptionId, false);
            options.SetOptionValue(DefaultOptions.TabSizeOptionId, 4);
            options.SetOptionValue(DefaultOptions.IndentSizeOptionId, 4);
        }
    }
}
