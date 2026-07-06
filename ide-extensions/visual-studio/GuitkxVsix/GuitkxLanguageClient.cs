using System;
using System.Collections.Generic;
using System.ComponentModel.Composition;
using System.Diagnostics;
using System.IO;
using System.Threading;
using System.Threading.Tasks;
using Microsoft.VisualStudio.LanguageServer.Client;
using Microsoft.VisualStudio.Shell;
using Microsoft.VisualStudio.Shell.Interop;
using Microsoft.VisualStudio.Threading;
using Microsoft.VisualStudio.Utilities;
using StreamJsonRpc;
using Task = System.Threading.Tasks.Task;

namespace GuitkxVsix
{
    // Launches the shared TypeScript language server (the same one VS Code uses) as a Node child
    // process over stdio. VS2022's LSP client is server-language-agnostic, so the Node server serves
    // both editors. The server bundle is copied next to this assembly under .\server (see the .csproj
    // content items), and a Windows Node runtime is bundled alongside it as .\server\node.exe so the
    // extension is self-contained -- no Node on the user's PATH required. We prefer that bundled
    // runtime and only fall back to a PATH `node` if it is somehow absent.
    // One client instance serves both content types -- mirroring VS Code's two-entry document
    // selector (guitkx always, gdscript when its setting is on) -- rather than spawning a second
    // server process. See GuitkxContentDefinition's doc comment for why the "Analyze plain .gd
    // files" option can't gate the gdscript attachment itself (MEF ContentType exports are static).
    [ContentType("guitkx")]
    [ContentType("gdscript")]
    [Export(typeof(ILanguageClient))]
    public sealed class GuitkxLanguageClient : ILanguageClient, ILanguageClientCustomMessage2
    {
        public string Name => "GUITKX Language Server";

        // ILanguageClientCustomMessage2: VS calls AttachForCustomMessageAsync once the connection's
        // JSON-RPC channel is up, handing us the exact JsonRpc instance the LSP client itself uses.
        // Format-on-save (GuitkxFormatOnSave.cs) needs this to send a raw textDocument/formatting
        // request -- there is no other supported way to reach the live RPC channel from outside the
        // LSP client's own request/response plumbing (ILanguageClientBroker's public surface is just
        // LoadAsync; it has no generic "send a request" method).
        public static JsonRpc Rpc { get; private set; }
        public object MiddleLayer => null;
        public object CustomMessageTarget => null;

        public Task AttachForCustomMessageAsync(JsonRpc rpc)
        {
            Rpc = rpc;
            return Task.CompletedTask;
        }

        // G-12: the shared server now has an onDidChangeConfiguration handler (server.ts
        // applyGuitkxOptions), so advertising this section is no longer decoration. We don't rely on
        // it alone, though -- it isn't documented whether/when VS's LSP client host sends
        // workspace/didChangeConfiguration off it for a client whose settings live in a custom
        // WritableSettingsStore rather than VS's own settings change events. GuitkxOptionsPage.OnApply
        // sends the same notification explicitly and unconditionally, so the update is delivered
        // regardless of whether this also fires (the server re-applying the same values twice is
        // harmless).
        public IEnumerable<string> ConfigurationSections => new[] { "guitkx" };

        public object InitializationOptions
        {
            get
            {
                // Unlike the DialogPage/RDT call sites (definitely UI thread), it isn't documented
                // which thread VS's LSP client host reads this property on -- switch explicitly
                // rather than asserting, so a background-thread read doesn't crash server startup.
                var options = ThreadHelper.JoinableTaskFactory.Run(async () =>
                {
                    await ThreadHelper.JoinableTaskFactory.SwitchToMainThreadAsync();
                    return GuitkxSettings.Read(ServiceProvider.GlobalProvider);
                });
                return BuildOptions(options);
            }
        }

        // G-20: also send enableGdscriptAnalysis -- the server-side gate for plain-.gd analysis
        // (VS2022 has no client-side selector-gating mechanism the way VS Code does, so this is the
        // only enforcement it gets). Shared with the explicit didChangeConfiguration notify below so
        // the initial and live-updated option bags can never drift apart.
        internal static object BuildOptions(GuitkxSettings.Options options) => new
        {
            enableEmbeddedAnalysis = options.EnableEmbeddedAnalysis,
            useGdformat = options.UseGdformat,
            enableGdscriptAnalysis = options.EnableGdscriptAnalysis,
        };

        public IEnumerable<string> FilesToWatch => null;
        public bool ShowNotificationOnInitializeFailed => true;

        public event AsyncEventHandler<EventArgs> StartAsync;
        public event AsyncEventHandler<EventArgs> StopAsync;

        // Tracked for the "Restart Language Server" command (GuitkxRestartCommand.cs). There is no
        // documented/supported manual reload API for a legacy MEF ILanguageClient (confirmed:
        // ILanguageClientBroker's only public member is LoadAsync -- no Stop/Restart/Reload; a
        // Microsoft Q&A-documented LoadAsync-again workaround is reported to work only once per
        // client instance, with a related Roslyn issue showing a shutdown race on repeat attempts).
        // Killing our own child process and leaning on VS's documented automatic single-restart of a
        // crashed language server is the more reliable of the unreliable options -- it's a real,
        // observed VS behavior, not an undocumented manual-reload call.
        private static Process _currentProcess;

        // G-22: VS's documented crash recovery restarts a language server ONCE per client instance.
        // The FIRST RequestRestart() spends that one auto-restart; a SECOND kill in the same session
        // has no budget left and VS will not bring the process back on its own. Tracked so the
        // command's message can tell the user the difference instead of promising a restart that
        // will not happen.
        private static int _restartCount;

        /// <summary>
        /// Kills the running server process, if any, so VS's own crash-recovery restarts it.
        /// Returns false if there was nothing running to kill. <paramref name="budgetExhausted"/> is
        /// true when this is the second-or-later restart THIS session -- VS's one-time auto-restart
        /// was already spent by an earlier call, so this kill will NOT come back on its own.
        /// </summary>
        public static bool RequestRestart(out bool budgetExhausted)
        {
            budgetExhausted = _restartCount >= 1;
            var process = _currentProcess;
            if (process == null)
                return false;
            try
            {
                if (!process.HasExited)
                    process.Kill();
                _restartCount++;
                return true;
            }
            catch (InvalidOperationException)
            {
                // Already exited between the HasExited check and Kill() -- treat as "nothing to do",
                // not a failure the user needs to see.
                return false;
            }
        }

        // G-22: the child's stderr was never captured, so a server-side crash or a slow/misbehaving
        // process (the exact conditions RequestRestart/format-on-save's G-18 timeout exist for) left
        // no trace anywhere in VS -- only a silent hang or a mysteriously-dead language server. Piped
        // to a dedicated Output-window pane instead.
        private static readonly Guid OutputPaneGuid = new Guid("2f6a1d3c-8b7e-4b1a-9c3d-6e2f4a8b5c7d");
        private static IVsOutputWindowPane _outputPane;

        private static IVsOutputWindowPane GetOrCreateOutputPane()
        {
            ThreadHelper.ThrowIfNotOnUIThread();
            if (_outputPane != null)
                return _outputPane;
            if (!(ServiceProvider.GlobalProvider.GetService(typeof(SVsOutputWindow)) is IVsOutputWindow outputWindow))
                return null;
            var paneGuid = OutputPaneGuid;
            outputWindow.CreatePane(ref paneGuid, "GUITKX Language Server", 1, 1);
            outputWindow.GetPane(ref paneGuid, out _outputPane);
            return _outputPane;
        }

        private static void LogServerStderr(string line)
        {
            ThreadHelper.JoinableTaskFactory.RunAsync(async () =>
            {
                await ThreadHelper.JoinableTaskFactory.SwitchToMainThreadAsync();
                GetOrCreateOutputPane()?.OutputStringThreadSafe(line + Environment.NewLine);
            }).FileAndForget("guitkx/serverStderr");
        }

        public async Task<Connection> ActivateAsync(CancellationToken token)
        {
            await Task.Yield();
            var dir = Path.GetDirectoryName(typeof(GuitkxLanguageClient).Assembly.Location);
            var serverDir = Path.Combine(dir, "server");
            var serverPath = Path.Combine(serverDir, "server.js");
            if (!File.Exists(serverPath))
                return null;

            // Prefer the Node runtime bundled in the VSIX; fall back to `node` on PATH if absent.
            var bundledNode = Path.Combine(serverDir, "node.exe");
            var nodeExe = File.Exists(bundledNode) ? bundledNode : "node";

            var info = new ProcessStartInfo
            {
                FileName = nodeExe,
                Arguments = $"\"{serverPath}\" --stdio",
                RedirectStandardInput = true,
                RedirectStandardOutput = true,
                RedirectStandardError = true,
                UseShellExecute = false,
                CreateNoWindow = true,
                WorkingDirectory = dir,
            };

            var process = new Process { StartInfo = info };
            // VSTHRD010 wants a main-thread switch before calling LogServerStderr, but
            // ErrorDataReceived's delegate is SYNCHRONOUS (fires on Process's own background I/O
            // thread) -- there is no `await` to be had here. LogServerStderr's own body already
            // does the switch correctly via JoinableTaskFactory.RunAsync + FileAndForget; asserting
            // main-thread AT this call site is not possible, not just inconvenient.
#pragma warning disable VSTHRD010
            process.ErrorDataReceived += (sender, args) =>
            {
                if (!string.IsNullOrEmpty(args.Data))
                    LogServerStderr(args.Data);
            };
#pragma warning restore VSTHRD010
            if (process.Start())
            {
                _currentProcess = process;
                process.BeginErrorReadLine();
                return new Connection(process.StandardOutput.BaseStream, process.StandardInput.BaseStream);
            }
            return null;
        }

        public async Task OnLoadedAsync()
        {
            if (StartAsync != null)
                await StartAsync.InvokeAsync(this, EventArgs.Empty);
        }

        public Task OnServerInitializedAsync() => Task.CompletedTask;

        public Task<InitializationFailureContext> OnServerInitializeFailedAsync(ILanguageClientInitializationInfo initializationState)
        {
            return Task.FromResult(new InitializationFailureContext
            {
                FailureMessage = "GUITKX language server failed to start. The extension bundles its own Node " +
                                 "runtime (server\\node.exe); if it is missing, install Node.js and put it on PATH. " +
                                 initializationState.StatusMessage,
            });
        }
    }
}
