const { spawnSync } = require("node:child_process");
const path = require("node:path");

const repoRoot = path.resolve(__dirname, "..");
const args = process.argv.slice(2);

function mapWindowsArgs(values) {
  return values.map((value) => {
    if (value === "--dry-run") {
      return "-DryRun";
    }
    return value;
  });
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
