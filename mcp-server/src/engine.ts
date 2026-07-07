import { spawn, type ChildProcessWithoutNullStreams } from "node:child_process";
import { fileURLToPath } from "node:url";
import { dirname, join } from "node:path";
import { createInterface, type Interface } from "node:readline";

const here = dirname(fileURLToPath(import.meta.url));
// dist/engine.js or src/engine.ts -> the host script lives one level up.
const HOST_SCRIPT = join(here, "..", "engine-host.ps1");

/** One engine response: the result rows plus whether the write gate downgraded the call to a preview. */
export interface EngineResult {
  data: unknown;
  downgraded: boolean;
}

interface Pending {
  resolve: (value: EngineResult) => void;
  reject: (err: Error) => void;
}

/**
 * Manages a single long-lived `pwsh` host process that owns the OpenGateSP module and the
 * SharePoint connection. Requests/responses are correlated by id over a JSON-lines protocol.
 */
export class EngineHost {
  private proc: ChildProcessWithoutNullStreams | null = null;
  private rl: Interface | null = null;
  private pending = new Map<string, Pending>();
  private seq = 0;
  private ready: Promise<void> | null = null;

  private start(): Promise<void> {
    if (this.ready) return this.ready;

    this.ready = new Promise<void>((resolve, reject) => {
      const pwsh = process.env.OPENGATESP_PWSH ?? "pwsh";
      const proc = spawn(pwsh, ["-NoProfile", "-NoLogo", "-File", HOST_SCRIPT], {
        stdio: ["pipe", "pipe", "pipe"],
      });
      this.proc = proc;

      proc.on("error", (err) => reject(err));
      proc.stderr.on("data", (chunk: Buffer) =>
        process.stderr.write(`[engine-host] ${chunk.toString()}`),
      );

      const rl = createInterface({ input: proc.stdout });
      this.rl = rl;
      rl.on("line", (raw) => {
        const line = raw.trim();
        if (!line) return;
        let msg: Record<string, unknown>;
        try {
          msg = JSON.parse(line);
        } catch {
          process.stderr.write(`[engine-host non-json] ${line}\n`);
          return;
        }
        if (msg.ready === true) {
          resolve();
          return;
        }
        const id = msg.id as string | undefined;
        if (!id) return;
        const p = this.pending.get(id);
        if (!p) return;
        this.pending.delete(id);
        if (msg.ok) p.resolve({ data: msg.data, downgraded: msg.downgraded === true });
        else p.reject(new Error((msg.error as string) || "engine error"));
      });

      proc.on("exit", (code) => {
        const err = new Error(`engine host exited (code ${code ?? "unknown"})`);
        for (const p of this.pending.values()) p.reject(err);
        this.pending.clear();
        this.proc = null;
        this.ready = null;
      });
    });

    return this.ready;
  }

  /** Run an engine command and resolve with its parsed data plus the write-gate downgrade flag. */
  async call(command: string, params: Record<string, unknown> = {}): Promise<EngineResult> {
    await this.start();
    const id = `r${++this.seq}`;
    return new Promise<EngineResult>((resolve, reject) => {
      this.pending.set(id, { resolve, reject });
      this.proc!.stdin.write(`${JSON.stringify({ id, command, params })}\n`);
    });
  }

  stop(): void {
    this.proc?.kill();
  }
}
