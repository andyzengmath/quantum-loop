# Contract Shapes Reference

Language-specific examples for generating `shape` and `definition` fields in `contracts.shared_types` entries. Load this reference when generating structural contracts for shared types detected across 2+ stories.

---

## Language Detection

Detect the project language from config files in the repository root. Use the first match in priority order:

| Config File | Language | `definition` Syntax |
|---|---|---|
| `tsconfig.json` | TypeScript | `export interface` / `export type` |
| `pyproject.toml` | Python | `class X(Protocol)` / `@dataclass class X` |
| `setup.py` | Python | `class X(Protocol)` / `@dataclass class X` |
| `go.mod` | Go | `type X interface` / `type X struct` |

If multiple config files exist (e.g., both `tsconfig.json` and `pyproject.toml`), use the `definitionFile` extension as tiebreaker: `.ts` means TypeScript, `.py` means Python, `.go` means Go.

---

## TypeScript

### Interface Example

When the shared type defines a structural contract with methods and properties:

**shape JSON:**
```json
{
  "properties": [
    { "name": "id", "type": "string", "readonly": true },
    { "name": "title", "type": "string" },
    { "name": "priority", "type": "'high' | 'medium' | 'low'" },
    { "name": "completedAt", "type": "Date | null" }
  ],
  "methods": [
    {
      "name": "validate",
      "params": [],
      "returns": "boolean"
    },
    {
      "name": "toJSON",
      "params": [],
      "returns": "Record<string, unknown>"
    }
  ]
}
```

**definition string:**
```
"export interface Task {\n  readonly id: string;\n  title: string;\n  priority: 'high' | 'medium' | 'low';\n  completedAt: Date | null;\n  validate(): boolean;\n  toJSON(): Record<string, unknown>;\n}"
```

**Full contract entry:**
```json
{
  "value": "Task",
  "pattern": "^[A-Z][a-zA-Z]*$",
  "definitionFile": "src/shared/types/task.ts",
  "owner": "US-001",
  "consumers": ["US-002", "US-003"],
  "shape": {
    "properties": [
      { "name": "id", "type": "string", "readonly": true },
      { "name": "title", "type": "string" },
      { "name": "priority", "type": "'high' | 'medium' | 'low'" },
      { "name": "completedAt", "type": "Date | null" }
    ],
    "methods": [
      { "name": "validate", "params": [], "returns": "boolean" },
      { "name": "toJSON", "params": [], "returns": "Record<string, unknown>" }
    ]
  },
  "definition": "export interface Task {\n  readonly id: string;\n  title: string;\n  priority: 'high' | 'medium' | 'low';\n  completedAt: Date | null;\n  validate(): boolean;\n  toJSON(): Record<string, unknown>;\n}"
}
```

### Type Alias Example

When the shared type is a union, enum-like, or mapped type:

**shape JSON:**
```json
{
  "properties": [
    { "name": "kind", "type": "'success' | 'error'" },
    { "name": "data", "type": "T | null" },
    { "name": "error", "type": "string | null" }
  ],
  "methods": []
}
```

**definition string:**
```
"export type Result<T> = {\n  kind: 'success' | 'error';\n  data: T | null;\n  error: string | null;\n};"
```

---

## Python

### Protocol Example

Use `Protocol` when the shared type defines a behavioral interface (duck typing contract):

**shape JSON:**
```json
{
  "properties": [
    { "name": "name", "type": "str" },
    { "name": "version", "type": "int" }
  ],
  "methods": [
    {
      "name": "process",
      "params": [
        { "name": "data", "type": "bytes" }
      ],
      "returns": "dict[str, Any]"
    },
    {
      "name": "validate",
      "params": [],
      "returns": "bool"
    }
  ]
}
```

**definition string:**
```
"from typing import Any, Protocol\n\nclass Processor(Protocol):\n    name: str\n    version: int\n\n    def process(self, data: bytes) -> dict[str, Any]: ...\n    def validate(self) -> bool: ..."
```

**Full contract entry:**
```json
{
  "value": "Processor",
  "definitionFile": "src/shared/processor.py",
  "owner": "US-001",
  "consumers": ["US-002", "US-004"],
  "shape": {
    "properties": [
      { "name": "name", "type": "str" },
      { "name": "version", "type": "int" }
    ],
    "methods": [
      {
        "name": "process",
        "params": [{ "name": "data", "type": "bytes" }],
        "returns": "dict[str, Any]"
      },
      {
        "name": "validate",
        "params": [],
        "returns": "bool"
      }
    ]
  },
  "definition": "from typing import Any, Protocol\n\nclass Processor(Protocol):\n    name: str\n    version: int\n\n    def process(self, data: bytes) -> dict[str, Any]: ...\n    def validate(self) -> bool: ..."
}
```

### @dataclass Example

Use `@dataclass` when the shared type is a data container with no abstract methods:

**shape JSON:**
```json
{
  "properties": [
    { "name": "id", "type": "str" },
    { "name": "title", "type": "str" },
    { "name": "priority", "type": "str" },
    { "name": "tags", "type": "list[str]" }
  ],
  "methods": []
}
```

**definition string:**
```
"from dataclasses import dataclass\n\n@dataclass\nclass TaskItem:\n    id: str\n    title: str\n    priority: str\n    tags: list[str]"
```

---

## Go

### Interface Example

Use `interface` when the shared type defines a behavioral contract:

**shape JSON:**
```json
{
  "properties": [],
  "methods": [
    {
      "name": "Process",
      "params": [
        { "name": "ctx", "type": "context.Context" },
        { "name": "data", "type": "[]byte" }
      ],
      "returns": "(Result, error)"
    },
    {
      "name": "Close",
      "params": [],
      "returns": "error"
    }
  ]
}
```

**definition string:**
```
"package shared\n\nimport \"context\"\n\ntype Handler interface {\n\tProcess(ctx context.Context, data []byte) (Result, error)\n\tClose() error\n}"
```

**Full contract entry:**
```json
{
  "value": "Handler",
  "definitionFile": "internal/shared/handler.go",
  "owner": "US-002",
  "consumers": ["US-003", "US-005"],
  "shape": {
    "properties": [],
    "methods": [
      {
        "name": "Process",
        "params": [
          { "name": "ctx", "type": "context.Context" },
          { "name": "data", "type": "[]byte" }
        ],
        "returns": "(Result, error)"
      },
      {
        "name": "Close",
        "params": [],
        "returns": "error"
      }
    ]
  },
  "definition": "package shared\n\nimport \"context\"\n\ntype Handler interface {\n\tProcess(ctx context.Context, data []byte) (Result, error)\n\tClose() error\n}"
}
```

### Struct Example

Use `struct` when the shared type is a data container:

**shape JSON:**
```json
{
  "properties": [
    { "name": "ID", "type": "string" },
    { "name": "Name", "type": "string" },
    { "name": "Priority", "type": "int" },
    { "name": "Tags", "type": "[]string" }
  ],
  "methods": []
}
```

**definition string:**
```
"package shared\n\ntype TaskItem struct {\n\tID       string   `json:\"id\"`\n\tName     string   `json:\"name\"`\n\tPriority int      `json:\"priority\"`\n\tTags     []string `json:\"tags\"`\n}"
```

---

## Guidance: When to Generate `definition` vs Shape-Only

### Generate both `shape` and `definition` when:

- **`consumers.length >= 2`** -- multiple agents will import this type. The `definition` ensures all consumers see identical code. The materializer writes the `definition` verbatim to `definitionFile` before agents are spawned.
- The type has methods or complex generics that `shape` alone cannot fully capture.

### Generate `shape` only (no `definition`) when:

- **Advisory contracts** -- the type is referenced by only one consumer, so materialization is skipped. The `shape` serves as documentation for the implementing agent.
- The exact syntax is flexible (e.g., the consumer may use `interface` or `type` interchangeably).
- The type is simple enough that `shape` is unambiguous (e.g., a flat struct with primitive fields).

### Decision table:

| Condition | `shape` | `definition` | Materialized? |
|---|---|---|---|
| `consumers.length >= 2` | Yes | Yes | Yes -- written to disk before wave |
| `consumers.length == 1` | Yes | Optional | No -- advisory only |
| `consumers.length == 0` (owner only) | Optional | No | No |

### Shape field conventions:

- `properties[].type` uses the target language's type syntax (e.g., `string` for TS, `str` for Python, `string` for Go)
- `properties[].readonly` is optional, defaults to `false`. Only meaningful for TypeScript (`readonly` keyword)
- `methods[].params` omits `self`/receiver for Python and Go -- the materializer adds it during generation
- `methods[].returns` uses the target language's return syntax (e.g., `(Result, error)` for Go multi-return)
- `methods` array is empty `[]` for pure data types (dataclasses, structs without methods)
