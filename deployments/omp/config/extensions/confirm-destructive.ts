import type { ExtensionAPI } from "@oh-my-pi/pi-coding-agent";

/**
 * Inverted permission model: every tool requires user confirmation UNLESS it
 * appears in ALWAYS_ALLOW (read-only / no side-effects) or in LSP_READONLY_ACTIONS.
 *
 * Any future tool added to omp will be blocked by default until explicitly
 * allowlisted here — this avoids the arms race of pattern-matching dangerous
 * commands.
 *
// Auto-loaded from: ~/.omp/agent/extensions/confirm-destructive.ts
 */

// ---------------------------------------------------------------------------
// Tools that are purely read-only and carry no side effects.
// Everything NOT in this set will require confirmation.
// ---------------------------------------------------------------------------
const ALWAYS_ALLOW = new Set([
    "read",        // read files / directories
    "search",      // search file content (was "grep")
    "find",        // find files by glob
    "ast_grep",    // structural code search (read-only)
    "calc",        // deterministic calculator
    "ask",         // ask the user a question
    "poll",        // block on async jobs (no side effects)
    "todo_write",  // internal task-tracking state only
]);

// LSP actions that are purely read-only (diagnostics, navigation, hover, etc.)
// Modifying LSP actions (rename, code_actions, reload) will fall through to
// the confirmation prompt.
const LSP_READONLY_ACTIONS = new Set([
    "diagnostics",
    "definition",
    "type_definition",
    "implementation",
    "references",
    "hover",
    "symbols",
    "status",
]);

// ---------------------------------------------------------------------------
// Build a human-readable summary of what a tool call is about to do so the
// user can make an informed decision in the confirmation dialog.
// ---------------------------------------------------------------------------
type Input = Record<string, unknown>;

function summarize(toolName: string, input: Input): string {
    const str = (v: unknown, fallback = ""): string =>
        v !== undefined && v !== null ? String(v) : fallback;

    const preview = (text: string, maxLines = 30): string => {
        const lines = text.split("\n");
        return lines.length > maxLines
            ? lines.slice(0, maxLines).join("\n") + `\n… (${lines.length - maxLines} more lines)`
            : text;
    };

    switch (toolName) {
        case "bash":
        case "shell":
            return str(input.command);
        case "python":
            return preview(str(input.code));
        case "write":
            return `path: ${input.path}\n---\n${preview(str(input.content))}`;
        case "edit":
            return `input:\n${preview(str(input.input))}`;
        case "ast_edit":
            return `path: ${input.path}  rule: ${str(input.rule ?? input.pattern)}`;
        case "notebook":
            return `path: ${input.path ?? input.file}  action: ${str(input.action ?? "edit")}`;
        case "ssh":
            return `[${input.host}] ${input.command}`;
        case "browser":
            return `action: ${input.action}  url/selector: ${str(input.url ?? input.selector)}`;
        case "task":
            return preview(str(input.description ?? input.prompt ?? JSON.stringify(input)));
        case "lsp":
            return `action: ${input.action}  file: ${str(input.file ?? "workspace")}`;
        case "generate_image":
            return str(input.prompt);
        default:
            return preview(JSON.stringify(input, null, 2));
    }
}

// ---------------------------------------------------------------------------
export default function (omp: ExtensionAPI) {
    omp.on("tool_call", async (event, ctx) => {
        // Unconditionally allow read-only tools
        if (ALWAYS_ALLOW.has(event.toolName)) return undefined;

        // Allow read-only LSP actions; prompt for modifying ones
        if (event.toolName === "lsp") {
            const action = String((event.input as Input).action ?? "");
            if (LSP_READONLY_ACTIONS.has(action)) return undefined;
        }

        // Non-interactive mode (omp -p, omp commit, --mode rpc, subagents):
        // ctx.ui.confirm returns false without prompting, which would silently
        // block every tool. Allow through instead — non-interactive invocations
        // are explicit user decisions.
        if (!ctx.hasUI) return undefined;

        const detail = summarize(event.toolName, event.input as Input);
        const ok = await ctx.ui.confirm(`Allow tool: ${event.toolName}`, detail);
        if (!ok) return { block: true, reason: "Blocked by user" };
        return undefined;
    });
}
