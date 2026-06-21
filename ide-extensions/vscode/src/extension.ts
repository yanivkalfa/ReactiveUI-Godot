import * as path from "path";
import * as fs from "fs";
import { workspace, ExtensionContext, window } from "vscode";
import {
  LanguageClient,
  LanguageClientOptions,
  ServerOptions,
  TransportKind,
} from "vscode-languageclient/node";

let client: LanguageClient | undefined;

export function activate(context: ExtensionContext): void {
  // The language server is bundled under ./server (vsce copies lsp-server/out at package time).
  // In the dev tree we fall back to the sibling lsp-server build.
  const bundled = context.asAbsolutePath(path.join("server", "server.js"));
  const devFallback = context.asAbsolutePath(path.join("..", "lsp-server", "out", "server.js"));
  const serverModule = fs.existsSync(bundled) ? bundled : devFallback;

  if (!fs.existsSync(serverModule)) {
    window.showWarningMessage(
      "GUITKX: language server not found (syntax highlighting still works). Build ide-extensions/lsp-server."
    );
    return;
  }

  const serverOptions: ServerOptions = {
    run: { module: serverModule, transport: TransportKind.ipc },
    debug: {
      module: serverModule,
      transport: TransportKind.ipc,
      options: { execArgv: ["--nolazy", "--inspect=6009"] },
    },
  };

  const config = workspace.getConfiguration("guitkx");
  const clientOptions: LanguageClientOptions = {
    documentSelector: [{ scheme: "file", language: "guitkx" }],
    initializationOptions: {
      godotPort: config.get<number>("godotLanguageServerPort", 6005),
      enableGodotProxy: config.get<boolean>("enableGodotProxy", true),
    },
    synchronize: { configurationSection: "guitkx" },
  };

  client = new LanguageClient("guitkx", "GUITKX Language Server", serverOptions, clientOptions);
  client.start();
}

export function deactivate(): Thenable<void> | undefined {
  return client?.stop();
}
