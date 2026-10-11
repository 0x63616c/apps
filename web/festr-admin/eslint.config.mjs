import nextVitals from "eslint-config-next/core-web-vitals";
import nextTs from "eslint-config-next/typescript";
import shadcn from "eslint-plugin-shadcn";
import { defineConfig, globalIgnores } from "eslint/config";

export default defineConfig([
  ...nextVitals,
  ...nextTs,
  {
    // Registry components stay byte-for-byte upstream (checked by `pnpm ui:check`); the shadcn rules cover app code.
    ...shadcn.configs["radix-all"],
    files: ["src/**/*.tsx"],
    ignores: ["src/components/ui/**"],
  },
  globalIgnores([".next/**", "node_modules/**", "next-env.d.ts", "drizzle/**"]),
]);
