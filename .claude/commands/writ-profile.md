---
description: Generate codebase profile (.writ/profile.json) and test map (.writ/test-map.json) via import graph analysis
allowed-tools: Read, Glob, Grep, Bash, Write
---

Profile the codebase and generate structured intelligence files that downstream
commands (`/writ-session`, `/writ-spec`, `/writ-diff`) use for codebase-aware planning.

Output: `.writ/profile.json` (file inventory, imports, exports, dependency graph)
and `.writ/test-map.json` (source-to-test mappings via import analysis).

Arguments: `$ARGUMENTS` is optional.
- `--language ts|js|py|go|rs` - override language auto-detection
- (empty) - auto-detect language and profile everything

## Step 1: Pre-flight

Create the `.writ/` directory if it does not exist:
```bash
mkdir -p .writ
```

If `.writ/profile.json` already exists, read its `generated_at` field and note:
"Previous profile generated at <timestamp>. Regenerating."

## Step 2: Detect project

Read whichever package manifest exists (check in this order):
- `package.json` - extract `name`, detect framework from `dependencies` (express, next, fastapi, etc.), note `main`/`bin` fields as entry points
- `pyproject.toml` - extract project name, detect framework
- `Cargo.toml` - extract package name
- `go.mod` - extract module path
- `Gemfile` - note Ruby project
- `pom.xml` / `build.gradle` - note Java project

From the manifest, determine:
- **project name** (from manifest `name` field, or directory name as fallback)
- **primary language** (from file extensions and manifest type)
- **framework** (from dependencies: express, next, fastapi, flask, gin, etc., or empty)
- **package manager** (npm/yarn/pnpm from lockfile, pip, cargo, go, etc.)

If `$ARGUMENTS` contains `--language <lang>`, use that as the primary language override.

## Step 3: File inventory

Glob for all project files. Exclude these directories entirely:
- `node_modules`, `.git`, `dist`, `build`, `.next`, `coverage`
- `.writ/runs`, `__pycache__`, `.tox`, `.mypy_cache`, `.pytest_cache`
- `vendor` (Go), `target` (Rust), `.gradle`, `.mvn`

For each file, determine:

**Language** from extension:
| Extension | Language |
|-----------|----------|
| `.ts`, `.tsx` | typescript |
| `.js`, `.jsx`, `.mjs`, `.cjs` | javascript |
| `.py` | python |
| `.go` | go |
| `.rs` | rust |
| `.rb` | ruby |
| `.java` | java |
| `.vue`, `.svelte` | (use embedded script language) |

**Category** by path and name:
| Category | Detection rules |
|----------|----------------|
| `test` | Path contains `test/`, `tests/`, `spec/`, `__tests__/`, OR filename matches `*.test.*`, `*.spec.*`, `test_*.*`, `*_test.*` |
| `config` | Root-level dotfiles (`.eslintrc`, `.prettierrc`), `*.config.*`, `tsconfig*.json`, package manifests, `*.yml`/`*.yaml` in project root |
| `docs` | `*.md` files, anything under `docs/` |
| `generated` | Files under `dist/`, `build/`, `.next/`, `coverage/`, `out/` |
| `script` | Files under `scripts/`, `bin/`, or `*.sh` files |
| `source` | Everything else with a recognized language extension |

Track the discovered source and test directories for use in Steps 4-5.

## Step 4: Extract imports

Run language-specific ripgrep commands to extract import statements. Process BOTH
source files AND test files (test file imports are needed for the test map in Step 7).

Check if `rg` (ripgrep) is available:
```bash
command -v rg >/dev/null 2>&1
```
If not available, warn: "ripgrep (rg) not found, falling back to grep. Import extraction may be less accurate." Use grep equivalents below.

### TypeScript / JavaScript

```bash
# ES module imports: import X from 'path'
rg --no-heading --with-filename -n "from\s+['\"]([^'\"]+)['\"]" -o -r '$1' --glob '*.{ts,tsx,js,jsx,mjs,cjs}' .

# CommonJS requires: require('path')
rg --no-heading --with-filename -n "require\(\s*['\"]([^'\"]+)['\"]\s*\)" -o -r '$1' --glob '*.{ts,tsx,js,jsx,mjs,cjs}' .

# Re-exports: export * from 'path', export { x } from 'path'
rg --no-heading --with-filename -n "export\s+.*from\s+['\"]([^'\"]+)['\"]" -o -r '$1' --glob '*.{ts,tsx,js,jsx,mjs,cjs}' .

# Dynamic imports: import('path')
rg --no-heading --with-filename -n "import\(\s*['\"]([^'\"]+)['\"]\s*\)" -o -r '$1' --glob '*.{ts,tsx,js,jsx,mjs,cjs}' .
```

### Python

```bash
# from X import Y
rg --no-heading --with-filename -n "^from\s+(\S+)\s+import" -o -r '$1' --glob '*.py' .

# import X
rg --no-heading --with-filename -n "^import\s+(\S+)" -o -r '$1' --glob '*.py' .
```

### Go

```bash
# Single import: import "path"
rg --no-heading --with-filename -n '^\s*import\s+"([^"]+)"' -o -r '$1' --glob '*.go' .

# Block imports: lines inside import ( ... ) blocks containing quoted strings
rg --no-heading --with-filename -n '^\s+"([^"]+)"' -o -r '$1' --glob '*.go' .
```

### Rust

```bash
# use crate::path, use super::path, use path
rg --no-heading --with-filename -n "^use\s+((?:crate|super|self)?\S+)" -o -r '$1' --glob '*.rs' .

# mod declarations
rg --no-heading --with-filename -n "^mod\s+(\w+)" -o -r '$1' --glob '*.rs' .
```

### Grep fallback (if ripgrep unavailable)

For TypeScript/JavaScript:
```bash
grep -rnH "from ['\"]" --include='*.ts' --include='*.tsx' --include='*.js' --include='*.jsx' .
grep -rnH "require(" --include='*.ts' --include='*.tsx' --include='*.js' --include='*.jsx' .
```

### Resolving imports

For each extracted import:
1. **External imports**: Does not start with `.` or `/` (JS/TS), or is a known stdlib/third-party module (Python/Go). Mark with `"external": true`. Collect the package name in `stats.external_packages`.
2. **Local imports**: Starts with `.` or `/` (JS/TS), or is a project module (Python).
   - Resolve relative paths from the importing file's directory to a project-relative path.
   - Try extensions: if `./utils/helper` is imported, check for `utils/helper.ts`, `utils/helper.js`, `utils/helper/index.ts`, `utils/helper/index.js`.
   - Store as project-relative path (e.g., `src/utils/helper.ts`).

For each import, also extract imported symbols where possible. For ES imports
(`import { Router, Request } from 'express'`), capture `["Router", "Request"]`.
For bare imports (`import express from 'express'`), capture `["default"]`.
If symbols cannot be determined, use an empty array.

## Step 5: Extract exports

Run language-specific patterns to find what each file exports.

### TypeScript / JavaScript

```bash
# Named exports: export function/class/const/let/var/type/interface/enum Name
rg --no-heading --with-filename -n "^export\s+(default\s+)?(function|class|const|let|var|type|interface|enum)\s+(\w+)" -o -r '$3' --glob '*.{ts,tsx,js,jsx,mjs,cjs}' .

# Default export of identifier: export default Name
rg --no-heading --with-filename -n "^export\s+default\s+(\w+)" -o -r '$1' --glob '*.{ts,tsx,js,jsx,mjs,cjs}' .

# module.exports
rg --no-heading --with-filename -n "module\.exports\s*=" --glob '*.{js,cjs}' .
```

### Python

```bash
# Top-level function and class definitions (public only, no _ prefix)
rg --no-heading --with-filename -n "^(def|class)\s+([A-Za-z]\w*)" -o -r '$2' --glob '*.py' .

# __all__ list entries
rg --no-heading --with-filename -n "__all__\s*=\s*\[" --glob '*.py' .
```

Collect export names as a flat string array per file.

## Step 6: Build dependency graph

From the import data collected in Step 4, build an adjacency list where each
source file maps to the local files it depends on:

```
dependency_graph: {
  "src/routes/auth.ts": ["src/db/client.ts", "src/middleware/auth.ts"],
  "src/routes/users.ts": ["src/db/client.ts", "src/models/user.ts"]
}
```

Only include local imports (not external packages). Only include source files
(not test files) in the graph keys. Test file dependencies are handled in Step 7.

**Identify shared modules**: Find directories that appear as import targets from
3 or more different files. These are the project's utility/shared code directories
(e.g., `src/utils/`, `src/lib/`, `src/helpers/`, `src/common/`).

**Identify entry points** (files that are the "roots" of the dependency tree):
1. Files listed in `package.json` `main`, `bin`, or `exports` fields
2. Files named `index.ts`, `index.js`, `main.ts`, `main.py`, `app.ts`, `app.py`,
   `server.ts`, `server.js`, `main.go`, `main.rs` at the source root
3. Files that import other files but are not imported by any other source file

**Identify source directories**: Collect the unique top-level directories that
contain source files (e.g., `["src/", "lib/"]`). Similarly for test, config,
docs, and generated directories.

## Step 7: Build test map

From the imports extracted in Step 4, specifically from files with category `test`:

1. For each test file, find which source files it imports directly.
2. **One-hop transitivity**: If `auth.test.ts` imports `src/auth.ts`, and
   `src/auth.ts` imports `src/middleware.ts` (from the dependency graph), then
   `auth.test.ts` covers both `src/auth.ts` and `src/middleware.ts`.
   Limit to one hop to avoid mapping every test to every file.
3. Build **source_to_tests**: for each source file, list all test files that cover it.
4. Build **test_to_sources**: for each test file, list all source files it covers.
5. **unmapped_tests**: test files that import no source files (likely test helpers,
   fixtures, setup files).
6. **untested_sources**: source files that no test file covers.

Compute `coverage_ratio` = (number of source files with at least one test) / (total source files).

## Step 8: Write JSON files

Assemble and write both output files.

### `.writ/profile.json`

```json
{
  "version": "1.0.0",
  "generated_at": "<current ISO timestamp>",
  "project": {
    "name": "<project name>",
    "root": "<absolute path to project root>",
    "language": "<primary language>",
    "framework": "<detected framework or empty string>",
    "package_manager": "<detected package manager>"
  },
  "files": [
    {
      "path": "<project-relative path>",
      "category": "<source|test|config|docs|generated|script>",
      "language": "<language>",
      "exports": ["<export name>", "..."],
      "imports": [
        { "from": "<resolved project-relative path or package name>", "symbols": ["<name>"] },
        { "from": "<package>", "symbols": ["<name>"], "external": true }
      ]
    }
  ],
  "entry_points": ["<path>", "..."],
  "directories": {
    "source": ["<dir>/"],
    "test": ["<dir>/"],
    "config": ["."],
    "docs": ["<dir>/"],
    "generated": ["<dir>/"]
  },
  "dependency_graph": {
    "<source file>": ["<dependency>", "..."]
  },
  "shared_modules": ["<dir>/", "..."],
  "stats": {
    "total_files": 0,
    "source_files": 0,
    "test_files": 0,
    "config_files": 0,
    "languages": { "<language>": 0 },
    "total_imports": 0,
    "external_packages": ["<package>", "..."]
  }
}
```

### `.writ/test-map.json`

```json
{
  "version": "1.0.0",
  "generated_at": "<current ISO timestamp>",
  "source_to_tests": {
    "<source file>": ["<test file>", "..."]
  },
  "test_to_sources": {
    "<test file>": ["<source file>", "..."]
  },
  "unmapped_tests": ["<test helper>", "..."],
  "untested_sources": ["<source file>", "..."],
  "stats": {
    "source_files": 0,
    "test_files": 0,
    "mapped_pairs": 0,
    "coverage_ratio": 0.0
  }
}
```

Write both files using the Write tool. Use `python3 -c "import json; ..."` or
equivalent to validate the JSON is well-formed after writing.

## Step 9: Human-readable summary

Output:

```
=== Profile Complete ===

Profiled N files, found M imports, identified L test files.
Test coverage: X/Y source files have at least one test (Z%).
Entry points: <comma-separated list>
Shared modules: <comma-separated list>

Files written:
  .writ/profile.json    (N files, M imports)
  .writ/test-map.json   (X mapped pairs)

Next: /writ-spec "add feature description"
```

If the project has no test files, adjust: "No test files found. .writ/test-map.json
written with empty mappings."

## Error handling

All errors must include: what happened, why, and how to fix.

| Condition | Message |
|-----------|---------|
| No source files found | "No source files found in standard directories (src/, lib/, app/). Why: writ-profile looks for source code in conventional locations. Fix: ensure your project has source files, or check that the project root is correct." |
| Zero imports extracted | "No imports detected. Why: the project may use an unsupported language or non-standard import syntax. Fix: try `--language <lang>` to override auto-detection, or check that source files contain import statements." |
| ripgrep not found | "ripgrep (rg) not found, falling back to grep. Import extraction may be less accurate. Fix: install ripgrep for better results (brew install ripgrep / apt install ripgrep)." |
| No package manifest | "No package manifest found (package.json, pyproject.toml, etc.). Why: writ-profile uses the manifest to detect language and framework. Fix: profiling will continue with auto-detection from file extensions." |

## Known limitations

Document these in the summary output if relevant:
- Dynamic imports (`import()` in JS/TS) are captured but may not resolve correctly
- Barrel files (`export * from`) create indirect dependencies that may inflate the graph
- Path aliases (tsconfig `paths`, webpack aliases) are not resolved - imports using aliases appear as external
- Python relative imports within packages may not resolve correctly for deeply nested modules
- Monorepo internal package imports may appear as external
