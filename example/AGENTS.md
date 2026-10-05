# Example Libghostty Projects

Each example is a standalone project with its own `README.md`. Most C and
Zig examples have `build.zig`, `build.zig.zon`, and `src/main.c` (or `.zig`);
the CMake, Swift, and browser examples use their own build instructions.
Read the selected example's README before building it.

This fork's checked-in GitHub workflows do not include the upstream example
build matrix. Do not assume that adding an example runs or validates it in CI.

## Adding a New Example

1. For a Zig-built example, copy an existing directory
   (e.g., `c-vt-encode-focus/`) as a starting point.
2. Update `build.zig.zon`: change `.name`, generate a **new unique**
   `.fingerprint` value (a random `u64` hex literal), and keep
   `.minimum_zig_version` matching the others.
3. Update `build.zig`: change the executable `.name` to match the directory.
4. Write a `README.md` following the existing format.

## Doxygen Snippet Tags

Example source files use Doxygen `@snippet` tags so the corresponding
header in `include/ghostty/vt/` can reference them. Wrap the relevant
code with `//! [snippet-name]` markers:

```c
//! [my-snippet]
int main() { ... }
//! [my-snippet]
```

The header then uses `@snippet <dir>/src/main.c my-snippet` instead of
inline `@code` blocks. Never duplicate example code inline in the
headers — always use `@snippet`. When modifying example code, keep the
snippet markers in sync with the headers in `include/ghostty/vt/`.

## Conventions

- Executable names use underscores: `c_vt_encode_focus` (not hyphens).
- Zig-built C examples link `ghostty-vt` via `lazyDependency("ghostty", ...)`.
- `build.zig` files follow a common template — keep them consistent.
