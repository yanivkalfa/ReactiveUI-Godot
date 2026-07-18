using System.ComponentModel;
using Microsoft.VisualStudio.Shell;

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
        [Description("Type-aware completion/hover/go-to-definition inside {expr} and setup code, via the bundled gdscript-analyzer. Takes effect immediately (sent to the running language server, no restart needed).")]
        public bool EnableEmbeddedAnalysis { get; set; } = GuitkxSettings.Defaults.EnableEmbeddedAnalysis;

        [Category("Language server")]
        [DisplayName("Use gdformat for embedded reflow")]
        [Description("When gdformat (gdscript-toolkit) is installed, also reflow embedded GDScript on format. Takes effect immediately (sent to the running language server, no restart needed).")]
        public bool UseGdformat { get; set; } = GuitkxSettings.Defaults.UseGdformat;

        [Category("Language server")]
        [DisplayName("Analyze plain .gd files")]
        [Description("Diagnostics/completion/hover/etc. for plain .gd files, not just .guitkx. Takes effect immediately server-side (sent to the running language server). VS's MEF content-type registration is static, so the .gd document selector itself cannot be gated the way VS Code's can -- if another installed extension also claims .gd, this setting does not resolve that conflict, but turning it off does stop this extension's own .gd diagnostics/completion/etc.")]
        public bool EnableGdscriptAnalysis { get; set; } = GuitkxSettings.Defaults.EnableGdscriptAnalysis;

        [Category("Editor")]
        [DisplayName("Format .guitkx on save")]
        [Description("Send textDocument/formatting to the language server and apply the result before each save. Takes effect immediately (checked live by GuitkxFormatOnSave, not sent to the server) -- no restart needed for this one.")]
        public bool FormatOnSave { get; set; } = GuitkxSettings.Defaults.FormatOnSave;

        public override void LoadSettingsFromStorage()
        {
            ThreadHelper.ThrowIfNotOnUIThread();
            var options = GuitkxSettings.Read(ServiceProvider.GlobalProvider);
            EnableEmbeddedAnalysis = options.EnableEmbeddedAnalysis;
            UseGdformat = options.UseGdformat;
            EnableGdscriptAnalysis = options.EnableGdscriptAnalysis;
            FormatOnSave = options.FormatOnSave;
        }

        public override void SaveSettingsToStorage()
        {
            ThreadHelper.ThrowIfNotOnUIThread();
            GuitkxSettings.Write(ServiceProvider.GlobalProvider, new GuitkxSettings.Options
            {
                EnableEmbeddedAnalysis = EnableEmbeddedAnalysis,
                UseGdformat = UseGdformat,
                EnableGdscriptAnalysis = EnableGdscriptAnalysis,
                FormatOnSave = FormatOnSave,
            });
        }

        // G-12/G-20: the shared server now has an onDidChangeConfiguration handler that re-applies
        // guitkx.* live (server.ts applyGuitkxOptions), so an option change no longer needs a
        // restart -- send it the moment the user applies, the same instant GuitkxSettings.Write
        // (via base.OnApply -> SaveSettingsToStorage) persists it.
        protected override void OnApply(PageApplyEventArgs e)
        {
            base.OnApply(e);
            if (e.ApplyBehavior != ApplyKind.Apply)
                return;

            var rpc = GuitkxLanguageClient.Rpc;
            if (rpc == null)
                return; // server not attached yet -- it will read the fresh values at its own next InitializationOptions

            var payload = new
            {
                settings = new
                {
                    guitkx = GuitkxLanguageClient.BuildOptions(new GuitkxSettings.Options
                    {
                        EnableEmbeddedAnalysis = EnableEmbeddedAnalysis,
                        UseGdformat = UseGdformat,
                        EnableGdscriptAnalysis = EnableGdscriptAnalysis,
                        FormatOnSave = FormatOnSave,
                    }),
                },
            };
            ThreadHelper.JoinableTaskFactory.RunAsync(async () =>
                await rpc.NotifyWithParameterObjectAsync("workspace/didChangeConfiguration", payload))
                .FileAndForget("guitkx/didChangeConfiguration");
        }
    }
}
