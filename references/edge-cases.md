# Edge Case Testing Reference

Read this when writing tests for `testFirst` tasks. Field data shows 100% of post-implementation bugs were edge cases that passed happy-path tests.

## General Patterns (all languages)

- **Null/None/nil inputs** — every function that accepts optional parameters
- **Empty collections** — `[]`, `{}`, `""` — breaks `.sort()`, `sum()`, iteration
- **Boundary numbers** — 0, -1, MAX_INT, NaN, Infinity
- **Same identifier from different sources** — collision (e.g., same filename in different dirs)
- **Duplicate entries** — `.extend()` or `.push()` without dedup
- **Scale** — test with 1 item, 10 items, 100+ items (context pollution shows at scale)
- **String serialization of complex types** — `str(DataFrame)` produces multi-line output

## Python

| Gotcha | Why it breaks | Fix |
|--------|--------------|-----|
| `float('nan') == float('nan')` is `False` | NaN is never equal to itself | Use `math.isnan()` or `pd.isna()` |
| `None` in a list: `[1, None, 3]` | Breaks `.sort()`, `sum()`, comparisons | Filter or handle before operations |
| `Path.stem` vs `Path.name` | Same filename in different dirs produces same stem | Use full path or include parent in key |
| `str(DataFrame)` | Multi-line output breaks single-line parsers | Use `.to_json()` or `.to_dict()` |
| `.extend()` without dedup | Silently accumulates duplicates | Use `set()` or check before extending |
| `dict.update()` | Silently overwrites on key collision | Check for existing keys first |
| Mutable default args: `def f(x=[])` | Shared across all calls | Use `def f(x=None): x = x or []` |
| `json.dumps()` with non-serializable types | Raises `TypeError` at runtime | Test with datetime, Decimal, bytes |

## JavaScript / TypeScript

| Gotcha | Why it breaks | Fix |
|--------|--------------|-----|
| `typeof null === 'object'` | Null check with `typeof` misses null | Use `=== null` explicitly |
| `NaN !== NaN` | Equality check never matches NaN | Use `Number.isNaN()` |
| `[] + [] === ""` | Type coercion produces unexpected results | Use explicit type checks |
| `JSON.parse()` with trailing commas | Throws `SyntaxError` | Strip trailing commas or use JSON5 |
| `Array.sort()` mutates in-place | Original array modified unexpectedly | Use `[...arr].sort()` for immutable |
| `undefined` vs `null` vs missing key | Three different things | Test all three variations |
| `parseInt('08')` | Returns 0 in older engines (octal) | Always pass radix: `parseInt('08', 10)` |

## Go

| Gotcha | Why it breaks | Fix |
|--------|--------------|-----|
| nil slice vs empty slice | `len(nil) == 0` but `nil != []T{}` | Test both nil and empty |
| nil map read returns zero value | But nil map **write** panics | Initialize with `make(map[K]V)` |
| goroutine leak | Unbuffered channel with no receiver blocks forever | Use `context.WithCancel` or buffered channels |
| `defer` in a loop | Defers accumulate until function returns | Extract loop body to a function |
| `range` over map | Iteration order is random | Don't rely on order; sort keys if needed |
| String is bytes not chars | `len("日本")` is 6, not 2 | Use `utf8.RuneCountInString()` |
| Error wrapping | `errors.Is()` fails without `%w` in `fmt.Errorf` | Always use `fmt.Errorf("...: %w", err)` |

## Rust

| Gotcha | Why it breaks | Fix |
|--------|--------------|-----|
| `unwrap()` on None/Err | Panics at runtime | Use `?` operator or `match` |
| Integer overflow | Panics in debug, wraps silently in release | Use `checked_add()` or `saturating_add()` |
| `String` vs `&str` | Ownership confusion, unnecessary clones | Accept `&str`, return `String` |
| `Vec::drain()` | Invalidates indices during iteration | Collect indices first, drain in reverse |
| `.clone()` in a loop | Hidden O(n^2) performance | Use references or `Rc`/`Arc` |
