const { spawnSync } = require("node:child_process");
const path = require("node:path");

const repoRoot = path.resolve(__dirname, "..");
const args = process.argv.slice(2);

function mapWindowsArgs(values) {
  const mapped = [];

  for (let index = 0; index < values.length; index += 1) {
    const value = values[index];

    if (value === "--dry-run") {
      mapped.push("-DryRun");
      continue;
    }

    if (value === "--skip-git") {
      mapped.push("-SkipGit");
      continue;
    }

    if (value === "--skip-node") {
      mapped.push("-SkipNode");
      continue;
    }

    if (value === "--skip-npm") {
      mapped.push("-SkipNpm");
      continue;
    }

    if (value === "--codex-version") {
      const version = values[index + 1];
      if (!version) {
        throw new Error("--codex-version requires a value");
      }
      mapped.push("-CodexVersion", version);
      index += 1;
      continue;
    }

    if (value.startsWith("--codex-version=")) {
      const version = value.slice("--codex-version=".length);
      if (!version) {
        throw new Error("--codex-version requires a value");
      }
      mapped.push("-CodexVersion", version);
      continue;
    }

    mapped.push(value);
  }

  return mapped;
}

function run(command, commandArgs) {
  const result = spawnSync(command, commandArgs, {
    cwd: repoRoot,
    stdio: "inherit",
    shell: false,
  });

  if (result.error) {
    throw result.error;
  }

  process.exit(result.status ?? 1);
}

switch (process.platform) {
  case "win32": {
    const powershellExe = path.join(
      process.env.SystemRoot || "C:\\Windows",
      "System32",
      "WindowsPowerShell",
      "v1.0",
      "powershell.exe",
    );
    const scriptPath = path.join(repoRoot, "scripts", "bootstrap-codex-cli.ps1");
    run(powershellExe, [
      "-NoProfile",
      "-ExecutionPolicy",
      "Bypass",
      "-File",
      scriptPath,
      ...mapWindowsArgs(args),
    ]);
    break;
  }
  case "darwin": {
    const scriptPath = path.join(repoRoot, "scripts", "bootstrap-codex-cli-macos.sh");
    run("/bin/bash", [scriptPath, ...args]);
    break;
  }
  default:
    console.error(`[error] Unsupported platform: ${process.platform}`);
    process.exit(1);
}
