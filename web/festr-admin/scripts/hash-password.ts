import bcrypt from "bcryptjs";
import { createInterface } from "node:readline/promises";

// Usage: bun run hash-password            (prompts; input is not echoed)
//        echo -n 'secret' | bun run hash-password
async function readPassword(): Promise<string> {
  if (!process.stdin.isTTY) {
    const chunks: Buffer[] = [];
    for await (const chunk of process.stdin) chunks.push(chunk as Buffer);
    return Buffer.concat(chunks)
      .toString("utf8")
      .replace(/\r?\n$/, "");
  }
  const rl = createInterface({ input: process.stdin, output: process.stdout, terminal: true });
  const output = rl as unknown as { _writeToOutput: (s: string) => void };
  process.stdout.write("Password: ");
  output._writeToOutput = () => {};
  const password = await rl.question("");
  rl.close();
  process.stdout.write("\n");
  return password;
}

async function main() {
  const password = await readPassword();
  if (password.length < 12) throw new Error("Use at least 12 characters");
  const hash = await bcrypt.hash(password, 12);
  console.log(`\nVercel / shell:  ADMIN_PASSWORD_HASH=${hash}`);
  console.log(`.env.local:      ADMIN_PASSWORD_HASH=${hash.replace(/\$/g, "\\$")}`);
}

main().catch((err) => {
  console.error(err.message);
  process.exitCode = 1;
});
