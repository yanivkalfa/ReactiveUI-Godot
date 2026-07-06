using System;
using System.Runtime.InteropServices;
using System.Threading;
using Microsoft.VisualStudio;
using Microsoft.VisualStudio.ComponentModelHost;
using Microsoft.VisualStudio.Shell;
using Microsoft.VisualStudio.Shell.Interop;
using Task = System.Threading.Tasks.Task;

namespace GuitkxVsix
{
    // Hosts the GUITKX options page (Tools > Options > GUITKX) and the format-on-save RDT listener.
    // Background-autoloads on both the no-solution and solution-open UI contexts so it's sited as
    // early as VS allows -- this narrows (it cannot close; see GuitkxSettings) the race against
    // GuitkxLanguageClient.ActivateAsync, which is why option persistence goes through a settings
    // store instead of depending on this package being loaded.
    [PackageRegistration(UseManagedResourcesOnly = true, AllowsBackgroundLoading = true)]
    [Guid(PackageGuidString)]
    [ProvideOptionPage(typeof(GuitkxOptionsPage), "GUITKX", "Language Server", 0, 0, true)]
    [ProvideAutoLoad(VSConstants.UICONTEXT.NoSolution_string, PackageAutoLoadFlags.BackgroundLoad)]
    [ProvideAutoLoad(VSConstants.UICONTEXT.SolutionExists_string, PackageAutoLoadFlags.BackgroundLoad)]
    public sealed class GuitkxPackage : AsyncPackage
    {
        public const string PackageGuidString = "cb2d3574-abe7-4f6a-862b-0b7eeca7d2ac";

        private IVsRunningDocumentTable _rdt;
        private uint _formatOnSaveCookie;

        protected override async Task InitializeAsync(CancellationToken cancellationToken, IProgress<ServiceProgressData> progress)
        {
            await this.JoinableTaskFactory.SwitchToMainThreadAsync(cancellationToken);

            _rdt = await GetServiceAsync(typeof(SVsRunningDocumentTable)) as IVsRunningDocumentTable;
            var componentModel = await GetServiceAsync(typeof(SComponentModel)) as IComponentModel;
            if (_rdt != null && componentModel != null)
                _formatOnSaveCookie = GuitkxFormatOnSave.Advise(_rdt, componentModel);
        }

        protected override void Dispose(bool disposing)
        {
            // Only the disposing=true (deterministic Dispose) path touches the RDT -- never the
            // finalizer path (disposing=false), which must NOT assert UI-thread affinity (a
            // finalizer legitimately runs on a GC thread). VSTHRD108 wants the check unconditional,
            // but that would be actively wrong here -- this conditioning on `disposing` is the
            // standard, correct .NET dispose pattern, not something to restructure around the
            // analyzer. Suppressed deliberately, not to silence a real issue.
#pragma warning disable VSTHRD108
            if (disposing)
            {
                ThreadHelper.ThrowIfNotOnUIThread();
                if (_rdt != null && _formatOnSaveCookie != 0)
                {
                    _rdt.UnadviseRunningDocTableEvents(_formatOnSaveCookie);
                    _formatOnSaveCookie = 0;
                }
            }
#pragma warning restore VSTHRD108
            base.Dispose(disposing);
        }
    }
}
