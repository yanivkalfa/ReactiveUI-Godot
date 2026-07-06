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
using Task = System.Threading.Tasks.Task;

namespace GuitkxVsix
{
    // Launches the shared TypeScript language server (the same one VS Code uses) as a Node child
    // process over stdio. VS2022's LSP client is server-language-agnostic, so the Node server serves
    // both editors. The server bundle is copied next to this assembly under .\server (see the .csproj
    // content items), and a Windows Node runtime is bundled alongside it as .\server\node.exe so the
    // extension is self-contained -- no Node on the user's PATH required. We prefer that bundled
    // runtime and only fall back to a PATH `node` if it is somehow absent.
    [ContentType("guitkx")]
    [Export(typeof(ILanguageClient))]
    public sealed class GuitkxLanguageClient : ILanguageClient
    {
        public string Name => "GUITKX Language Server";

        // The shared server has no onDidChangeConfiguration handler, so advertising a configuration
        // section here would be pure decoration -- VS would send workspace/didChangeConfiguration
        // notifications that update nothing, implying live config sync that does not exist. null
        // (like FilesToWatch below) is the honest answer until the server gains that handler.
        public IEnumerable<string> ConfigurationSections => null;

        public object InitializationOptions
        {
            get
            {
                var options = GuitkxSettings.Read(ServiceProvider.GlobalProvider);
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
