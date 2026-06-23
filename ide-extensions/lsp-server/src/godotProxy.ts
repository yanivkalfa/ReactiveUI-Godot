// Proxy to Godot's built-in GDScript language server (raw TCP, default engine port 6005 — NOT
// 6008, which is godot-tools' own default). We connect as an LSP client, didOpen an in-memory
// virtual `.gd` document (full-text sync only — the server supports TextDocumentSyncKind.Full),
// and forward completion/hover. Requires a Godot editor running with the project open. All calls
// degrade gracefully (return null) when the editor is absent, so markup-side features still work.

import * as net from "net";

interface Pending {
  resolve: (v: any) => void;
  reject: (e: any) => void;
}

export class GodotProxy {
  private socket: net.Socket | null = null;
  private buffer = Buffer.alloc(0);
  private contentLength = -1;
  private nextId = 1;
  private pending = new Map<number, Pending>();
  private connecting: Promise<boolean> | null = null;
  private opened = new Map<string, number>(); // uri -> version
  ready = false;

  constructor(private host = "127.0.0.1", private port = 6005, private rootUri = "") {}

  /** Ensure a live connection; returns false if the editor LSP is unreachable. */
  async ensureConnected(): Promise<boolean> {
    if (this.ready && this.socket) return true;
    if (this.connecting) return this.connecting;
    this.connecting = new Promise<boolean>((resolve) => {
      const sock = net.connect(this.port, this.host);
      const fail = () => {
        this.ready = false;
        this.socket = null;
        this.connecting = null;
        resolve(false);
      };
      sock.setTimeout(2000, fail);
      sock.once("connect", async () => {
        sock.setTimeout(0);
        this.socket = sock;
        this.buffer = Buffer.alloc(0);
        this.contentLength = -1;
        try {
          await this.request("initialize", {
            processId: process.pid,
            rootUri: this.rootUri || null,
            capabilities: { textDocument: { completion: {}, hover: {}, definition: {}, publishDiagnostics: {} } },
          });
          this.notify("initialized", {});
          this.ready = true;
          this.connecting = null;
          resolve(true);
        } catch {
          fail();
        }
      });
      sock.on("data", (d) => this.onData(d));
      sock.once("error", fail);
      sock.once("close", () => {
        this.ready = false;
        this.socket = null;
        this.opened.clear();
        for (const p of this.pending.values()) p.reject(new Error("godot lsp closed"));
        this.pending.clear();
      });
    });
    return this.connecting;
  }

  /** didOpen (first time) or full-text didChange for the virtual doc at `uri`. */
  async sync(uri: string, text: string): Promise<void> {
    if (!(await this.ensureConnected())) return;
    const prev = this.opened.get(uri);
    if (prev === undefined) {
      this.opened.set(uri, 1);
      this.notify("textDocument/didOpen", {
        textDocument: { uri, languageId: "gdscript", version: 1, text },
      });
    } else {
      const version = prev + 1;
      this.opened.set(uri, version);
      this.notify("textDocument/didChange", {
        textDocument: { uri, version },
        contentChanges: [{ text }], // full-text replace
      });
    }
  }

  async completion(uri: string, line: number, character: number): Promise<any | null> {
    if (!(await this.ensureConnected())) return null;
    try {
      return await this.request("textDocument/completion", {
        textDocument: { uri },
        position: { line, character },
      });
    } catch {
      return null;
    }
  }

  async hover(uri: string, line: number, character: number): Promise<any | null> {
    if (!(await this.ensureConnected())) return null;
    try {
      return await this.request("textDocument/hover", {
        textDocument: { uri },
        position: { line, character },
      });
    } catch {
      return null;
    }
  }

  async definition(uri: string, line: number, character: number): Promise<any | null> {
    if (!(await this.ensureConnected())) return null;
    try {
      return await this.request("textDocument/definition", {
        textDocument: { uri },
        position: { line, character },
      });
    } catch {
      return null;
    }
  }

  // --- JSON-RPC over TCP with Content-Length framing ---

  private request(method: string, params: any): Promise<any> {
    return new Promise((resolve, reject) => {
      if (!this.socket) return reject(new Error("not connected"));
      const id = this.nextId++;
      this.pending.set(id, { resolve, reject });
      this.send({ jsonrpc: "2.0", id, method, params });
      setTimeout(() => {
        if (this.pending.has(id)) {
          this.pending.delete(id);
          reject(new Error(`timeout: ${method}`));
        }
      }, 3000);
    });
  }

  private notify(method: string, params: any): void {
    if (this.socket) this.send({ jsonrpc: "2.0", method, params });
  }

  private send(msg: any): void {
    const json = JSON.stringify(msg);
    const payload = Buffer.from(json, "utf8");
    this.socket!.write(`Content-Length: ${payload.length}\r\n\r\n`);
    this.socket!.write(payload);
  }

  private onData(data: Buffer): void {
    this.buffer = Buffer.concat([this.buffer, data]);
    while (true) {
      if (this.contentLength < 0) {
        const headerEnd = this.buffer.indexOf("\r\n\r\n");
        if (headerEnd < 0) return;
        const header = this.buffer.slice(0, headerEnd).toString("utf8");
        const m = /Content-Length:\s*(\d+)/i.exec(header);
        this.contentLength = m ? parseInt(m[1], 10) : 0;
        this.buffer = this.buffer.slice(headerEnd + 4);
      }
      if (this.buffer.length < this.contentLength) return;
      const body = this.buffer.slice(0, this.contentLength).toString("utf8");
      this.buffer = this.buffer.slice(this.contentLength);
      this.contentLength = -1;
      try {
        this.dispatch(JSON.parse(body));
      } catch {
        /* ignore malformed frame */
      }
    }
  }

  private dispatch(msg: any): void {
    if (msg.id !== undefined && (msg.result !== undefined || msg.error !== undefined)) {
      const p = this.pending.get(msg.id);
      if (p) {
        this.pending.delete(msg.id);
        if (msg.error) p.reject(msg.error);
        else p.resolve(msg.result);
      }
    }
    // server-initiated notifications (publishDiagnostics, etc.) are ignored for the proxy path
  }
}
