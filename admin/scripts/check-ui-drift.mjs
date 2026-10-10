// Fails if any installed shadcn/ui component differs from the registry beyond formatting.
// Uses the official CLI: `shadcn info --json` for the installed list, `shadcn add --dry-run` for the comparison.
import { execFileSync } from "node:child_process";

const shadcn = (args) =>
  execFileSync("pnpm", ["exec", "shadcn", ...args], { encoding: "utf8", stdio: ["ignore", "pipe", "pipe"] });

const info = JSON.parse(shadcn(["info", "--json"]));
const installed = info.components ?? info.installedComponents ?? [];
if (installed.length === 0) throw new Error("No installed components found in `shadcn info --json`");

const output = shadcn(["add", ...installed, "--dry-run", "--diff"]);
const drifted = [];
const blocks = output.split(/\n(?=├ )/);
for (const block of blocks) {
  const match = /├ (\S+) \((overwrite|create)\)/.exec(block);
  if (match && !block.includes("Formatting-only changes")) drifted.push(match[1]);
}
if (drifted.length) {
  console.error(`Components differ from the registry:\n  ${drifted.join("\n  ")}`);
  process.exit(1);
}
console.log(`shadcn/ui: ${installed.length} components match the registry`);
