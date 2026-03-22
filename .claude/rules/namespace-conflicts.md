# Namespace Conflicts

When two loaded packages export the same function name, use explicit `package::function()` notation for the conflicting functions.

## Known Conflicts

| Function | Packages | Resolution |
|----------|----------|------------|
| `filter()` | dplyr vs stats | Use `dplyr::filter()` or `stats::filter()` |
| `lag()` | dplyr vs stats | Use `dplyr::lag()` or `stats::lag()` |
| `set_caption()` | huxtable vs pharmaRTF | Use `huxtable::set_caption()` or `pharmaRTF::set_caption()` |
| `set_header_rows()` | huxtable vs pharmaRTF | Use explicit `package::` notation |

## Rule

- When huxtable and pharmaRTF are both loaded, always qualify shared function names with `package::`
- For all other packages, only qualify when a conflict actually exists — do not defensively namespace everything
