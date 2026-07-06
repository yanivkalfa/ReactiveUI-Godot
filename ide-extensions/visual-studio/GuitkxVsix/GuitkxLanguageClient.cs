using System;
using System.Collections.Generic;
using System.ComponentModel.Composition;
using System.Diagnostics;
using System.IO;
using System.Threading;
using System.Threading.Tasks;
using Microsoft.VisualStudio.LanguageServer.Client;
using Microsoft.VisualStudio.Shell;
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

        // The shared server has no onDidChangeConfiguration handler, so advertising a configuration
        // section here would be pure decoration -- VS would send workspace/didChangeConfiguration
        // notifications that update nothing, implying live config sync that does not exist. null
        // (like FilesToWatch below) is the honest answer until the server gains that handler.
        public IEnumerable<string> ConfigurationSections => null;

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
                return new
                {
                    enableEmbeddedAnalysis = options.EnableEmbeddedAnalysis,
                    useGdformat = options.UseGdformat,
                };
            }
        }

        public IEnumerable<string> FilesToWatch => null;
        public bool ShowNotificationOnInitializeFailed => true;

        public event AsyncEventHandler<EventArgs> StartAsync;
        public event AsyncEventHandler<EventArgs> StopAsync;

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
                UseShellExecute = false,
                CreateNoWindow = true,
                WorkingDirectory = dir,
            };

            var process = new Process { StartInfo = info };
            if (process.Start())
                return new Connection(process.StandardOutput.BaseStream, process.StandardInput.BaseStream);
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
