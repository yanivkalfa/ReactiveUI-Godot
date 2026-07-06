using System;
using System.ComponentModel.Design;
using System.Runtime.InteropServices;
using System.Threading;
using Microsoft.VisualStudio;
using Microsoft.VisualStudio.ComponentModelHost;
using Microsoft.VisualStudio.Shell;
using Microsoft.VisualStudio.Shell.Interop;
using Task = System.Threading.Tasks.Task;

namespace GuitkxVsix
{
    // Hosts the GUITKX options page (Tools > Options > GUITKX), the format-on-save RDT listener,
    // and the "Restart Language Server" command. Background-autoloads on both the no-solution and
    // solution-open UI contexts so it's sited as early as VS allows -- this narrows (it cannot
    // close; see GuitkxSettings) the race against GuitkxLanguageClient.ActivateAsync, which is why
    // option persistence goes through a settings store instead of depending on this package being
    // loaded.
    [PackageRegistration(UseManagedResourcesOnly = true, AllowsBackgroundLoading = true)]
    [Guid(PackageGuidString)]
    [ProvideMenuResource("Menus.ctmenu", 1)]
    [ProvideOptionPage(typeof(GuitkxOptionsPage), "GUITKX", "Language Server", 0, 0, true)]
    [ProvideAutoLoad(VSConstants.UICONTEXT.NoSolution_string, PackageAutoLoadFlags.BackgroundLoad)]
    [ProvideAutoLoad(VSConstants.UICONTEXT.SolutionExists_string, PackageAutoLoadFlags.BackgroundLoad)]
    public sealed class GuitkxPackage : AsyncPackage
    {
        public const string PackageGuidString = "cb2d3574-abe7-4f6a-862b-0b7eeca7d2ac";
        private const string CommandSetGuidString = "c085f8f3-5fb3-472f-af5b-745b81a840ff";
        private const int RestartLanguageServerCommandId = 0x0100;

        private IVsRunningDocumentTable _rdt;
        private uint _formatOnSaveCookie;

        protected override async Task InitializeAsync(CancellationToken cancellationToken, IProgress<ServiceProgressData> progress)
        {
            await this.JoinableTaskFactory.SwitchToMainThreadAsync(cancellationToken);

            _rdt = await GetServiceAsync(typeof(SVsRunningDocumentTable)) as IVsRunningDocumentTable;
            var componentModel = await GetServiceAsync(typeof(SComponentModel)) as IComponentModel;
            if (_rdt != null && componentModel != null)
                _formatOnSaveCookie = GuitkxFormatOnSave.Advise(_rdt, componentModel);

            if (await GetServiceAsync(typeof(IMenuCommandService)) is OleMenuCommandService commandService)
            {
                var commandId = new CommandID(new Guid(CommandSetGuidString), RestartLanguageServerCommandId);
                commandService.AddCommand(new MenuCommand(OnRestartLanguageServer, commandId));
            }
        }

        private void OnRestartLanguageServer(object sender, EventArgs e)
        {
            ThreadHelper.ThrowIfNotOnUIThread();
            var restarted = GuitkxLanguageClient.RequestRestart(out var budgetExhausted);
            // G-22: VS auto-restarts a crashed language server ONCE per session -- a second manual
            // kill has no budget left, so telling the user to just wait would be a false promise.
            string message;
            if (!restarted)
            {
                message = "No running GUITKX language server was found to restart (it may not have started " +
                           "yet, or a .guitkx/.gd file hasn't been opened this session).";
            }
            else if (budgetExhausted)
            {
                message = "The GUITKX language server process was stopped, but its automatic restart budget " +
                           "for this session is used up (Visual Studio only auto-restarts a crashed language " +
                           "server once) -- it will NOT come back on its own this time. Reload the solution or " +
                           "restart Visual Studio. See the \"GUITKX Language Server\" Output pane for the " +
                           "server's own log.";
            }
            else
            {
                message = "The GUITKX language server process was stopped and should restart automatically " +
                           "(Visual Studio restarts a crashed LSP server once). If it doesn't come back within " +
                           "a few seconds, check the \"GUITKX Language Server\" Output pane, then reload the " +
                           "solution or restart Visual Studio.";
            }
            VsShellUtilities.ShowMessageBox(
                this,
                message,
                "GUITKX",
                OLEMSGICON.OLEMSGICON_INFO,
                OLEMSGBUTTON.OLEMSGBUTTON_OK,
                OLEMSGDEFBUTTON.OLEMSGDEFBUTTON_FIRST);
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
