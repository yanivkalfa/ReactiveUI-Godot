using System.ComponentModel;
using Microsoft.VisualStudio.Shell;
using Microsoft.VisualStudio.Shell.Interop;

namespace GuitkxVsix
{
    // Tools > Options > GUITKX > Language Server. Mirrors the VS Code extension's three
    // guitkx.* settings. Persistence is overridden to route through GuitkxSettings' settings-store
    // collection instead of DialogPage's default reflection-derived registry path -- see
    // GuitkxSettings' doc comment for why that matters.
    public sealed class GuitkxOptionsPage : DialogPage
    {
        [Category("Language server")]
        [DisplayName("Enable embedded GDScript analysis")]
        [Description("Type-aware completion/hover/go-to-definition inside {expr} and setup code, via the bundled gdscript-analyzer. Takes effect on the next language server restart.")]
        public bool EnableEmbeddedAnalysis { get; set; } = GuitkxSettings.Defaults.EnableEmbeddedAnalysis;

        [Category("Language server")]
        [DisplayName("Use gdformat for embedded reflow")]
        [Description("When gdformat (gdscript-toolkit) is installed, also reflow embedded GDScript on format. Takes effect on the next language server restart.")]
        public bool UseGdformat { get; set; } = GuitkxSettings.Defaults.UseGdformat;

        [Category("Language server")]
        [DisplayName("Analyze plain .gd files")]
        [Description("Drive plain .gd files through gdscript-analyzer too (diagnostics, completion, hover, navigation, rename, formatting). Takes effect on the next language server restart.")]
        public bool EnableGdscriptAnalysis { get; set; } = GuitkxSettings.Defaults.EnableGdscriptAnalysis;

        public override void LoadSettingsFromStorage()
        {
            var options = GuitkxSettings.Read(ServiceProvider.GlobalProvider);
            EnableEmbeddedAnalysis = options.EnableEmbeddedAnalysis;
            UseGdformat = options.UseGdformat;
            EnableGdscriptAnalysis = options.EnableGdscriptAnalysis;
        }

        public override void SaveSettingsToStorage()
        {
            GuitkxSettings.Write(ServiceProvider.GlobalProvider, new GuitkxSettings.Options
            {
                EnableEmbeddedAnalysis = EnableEmbeddedAnalysis,
                UseGdformat = UseGdformat,
                EnableGdscriptAnalysis = EnableGdscriptAnalysis,
            });
        }

        // The shared server has no onDidChangeConfiguration handler (neither editor gets live
        // config sync -- see the parity plan's Phase 1 notes), so an option change needs a language
        // server restart to take effect. There is no restart command yet (planned separately);
        // reloading the solution/restarting VS is the interim workaround, same as instructed for
        // VS Code before its restart command existed.
        protected override void OnApply(PageApplyEventArgs e)
        {
            base.OnApply(e);
            if (e.ApplyBehavior != ApplyKind.Apply)
                return;

            VsShellUtilities.ShowMessageBox(
                Site,
                "Reload the solution (or restart Visual Studio) for this change to take effect. " +
                "A \"GUITKX: Restart Language Server\" command is planned to avoid the full reload.",
                "GUITKX",
                OLEMSGICON.OLEMSGICON_INFO,
                OLEMSGBUTTON.OLEMSGBUTTON_OK,
                OLEMSGDEFBUTTON.OLEMSGDEFBUTTON_FIRST);
        }
    }
}
