using System;
using System.Runtime.InteropServices;
using System.Threading;
using Microsoft.VisualStudio;
using Microsoft.VisualStudio.Shell;
using Task = System.Threading.Tasks.Task;

namespace GuitkxVsix
{
    // Hosts the GUITKX options page (Tools > Options > GUITKX). Background-autoloads on both the
    // no-solution and solution-open UI contexts so it's sited as early as VS allows -- this narrows
    // (it cannot close; see GuitkxSettings) the race against GuitkxLanguageClient.ActivateAsync,
    // which is why option persistence goes through a settings store instead of depending on this
    // package being loaded.
    [PackageRegistration(UseManagedResourcesOnly = true, AllowsBackgroundLoading = true)]
    [Guid(PackageGuidString)]
    [ProvideOptionPage(typeof(GuitkxOptionsPage), "GUITKX", "Language Server", 0, 0, true)]
    [ProvideAutoLoad(VSConstants.UICONTEXT.NoSolution_string, PackageAutoLoadFlags.BackgroundLoad)]
    [ProvideAutoLoad(VSConstants.UICONTEXT.SolutionExists_string, PackageAutoLoadFlags.BackgroundLoad)]
    public sealed class GuitkxPackage : AsyncPackage
    {
        public const string PackageGuidString = "cb2d3574-abe7-4f6a-862b-0b7eeca7d2ac";

        protected override Task InitializeAsync(CancellationToken cancellationToken, IProgress<ServiceProgressData> progress)
        {
            // Nothing to do on load today -- the options page is registered declaratively above, and
            // GuitkxLanguageClient reads settings directly from the settings store rather than through
            // this instance. Kept as a real AsyncPackage (not just a pkgdef-only registration) because
            // Phase 4's restart command needs a package to host it.
            return Task.CompletedTask;
        }
    }
}
