import * as path from "path";
import * as fs from "fs";
import { workspace, ExtensionContext, window, commands } from "vscode";
import {
  LanguageClient,
  LanguageClientOptions,
  ServerOptions,
  TransportKind,
} from "vscode-languageclient/node";

let client: LanguageClient | undefined;
let serverModule: string | undefined;

// G-13: `documentSelector` (specifically whether `gdscript` is in it at all) is read once at
// LanguageClient CONSTRUCTION time and frozen from then on -- client.restart() only stops/starts
// the SAME instance (vscode-languageclient's restart() is literally `stop(); start();`), so it
// never re-reads this. Toggling `guitkx.enableGdscriptAnalysis` therefore needs a brand new client
// object, not just a restarted one. (`enableEmbeddedAnalysis`/`useGdformat` don't have this problem
// -- they're synced live via `synchronize.configurationSection` + the server's
// onDidChangeConfiguration handler, so no client rebuild is needed for those.)
function buildAndStartClient(context: ExtensionContext, module: string): LanguageClient {
  const serverOptions: ServerOptions = {
    run: { module, transport: TransportKind.ipc },
    debug: {
      module,
      transport: TransportKind.ipc,
      options: { execArgv: ["--nolazy", "--inspect=6009"] },
    },
  };

  const config = workspace.getConfiguration("guitkx");
  const documentSelector = [{ scheme: "file", language: "guitkx" }];
  // On by default: also drive plain .gd files through gdscript-analyzer. It runs alongside godot-tools;
  // users disable that (or this `guitkx.enableGdscriptAnalysis` setting) to settle on one .gd LSP.
  if (config.get<boolean>("enableGdscriptAnalysis", true)) {
    documentSelector.push({ scheme: "file", language: "gdscript" });
  }
  const clientOptions: LanguageClientOptions = {
    documentSelector,
    initializationOptions: {
      enableEmbeddedAnalysis: config.get<boolean>("enableEmbeddedAnalysis", true),
      useGdformat: config.get<boolean>("useGdformat", true),
      enableGdscriptAnalysis: config.get<boolean>("enableGdscriptAnalysis", true),
    },
    synchronize: { configurationSection: "guitkx" },
  };

  const newClient = new LanguageClient("guitkx", "GUITKX Language Server", serverOptions, clientOptions);
  newClient.start();
  return newClient;
}

export function activate(context: ExtensionContext): void {
  // The language server is bundled under ./server (vsce copies lsp-server/out at package time).
  // In the dev tree we fall back to the sibling lsp-server build.
  const bundled = context.asAbsolutePath(path.join("server", "server.js"));
  const devFallback = context.asAbsolutePath(path.join("..", "lsp-server", "out", "server.js"));
  serverModule = fs.existsSync(bundled) ? bundled : devFallback;

  if (!fs.existsSync(serverModule)) {
    window.showWarningMessage(
      "GUITKX: language server not found (syntax highlighting still works). Build ide-extensions/lsp-server."
    );
    return;
  }

  client = buildAndStartClient(context, serverModule);

  // Lets the user recover the server without reloading the window (e.g. after a crash or a config
  // change). Mirrors uitkx's restart command.
  context.subscriptions.push(
    commands.registerCommand("guitkx.restartLanguageServer", async () => {
      if (!client) return;
      await client.restart();
      window.showInformationMessage("GUITKX: language server restarted.");
    })
  );

  // G-13: enableGdscriptAnalysis changed -- rebuild the client (see buildAndStartClient's comment)
  // so the .gd document selector reflects the new value, instead of leaving the user with a
  // toggle that visibly did nothing until they reloaded the window themselves.
  context.subscriptions.push(
    workspace.onDidChangeConfiguration(async (e) => {
      if (!e.affectsConfiguration("guitkx.enableGdscriptAnalysis") || !client || !serverModule) return;
      const old = client;
      await old.stop();
      client = buildAndStartClient(context, serverModule);
    })
  );
}

export function deactivate(): Thenable<void> | undefined {
  return client?.stop();
}
