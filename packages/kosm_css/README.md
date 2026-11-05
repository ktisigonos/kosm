# kosm_css

CSS for kosm: the `css` adapter, which claims `.css` files and enables `generate` and `block`.

`generate` writes every value as a custom property on `:root`. Nested structs join their names
with `-`, and `_` becomes `-`:

```zig
try output.generate(.{ .file = "~/.config/app/kosm.css" }, .{ .kosm = .{ .tab_bar = color } });
```

```css
:root {
  --kosm-tab-bar: #268078ff;
}
```

| Value | Written as |
|---|---|
| color | the file's color format; default `#rrggbbaa` (D61) |
| string | a quoted CSS string |
| integer, float | the number |
| `kosm.raw(text)` | `text`, verbatim (`10px`, `1px solid red`) |
| bool, list | an error: CSS has neither, so pass `kosm.raw` text |

`block` writes the same text between `/* kosm:begin <id> */` and `/* kosm:end */` in a CSS file
you otherwise write by hand (D72).
