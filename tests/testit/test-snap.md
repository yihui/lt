Snapshot tests for lt JSON specs.

```r
spec = function(x) x[lengths(x) > 0]
d = data.frame(x = 1:3, y = c("a", "b", "c"))
xfun::tojson(spec(lt(d)))
```
```
{
  "data": {
    "x": [1, 2, 3],
    "y": ["a", "b", "c"]
  }
}
```

```r
d = data.frame(x = 1:2, y = 3:4)
x = lt(d) |>
  lt_header("Title", "Subtitle") |>
  lt_spanner(Cols ~ x + y) |>
  lt_format(~ x, decimals = 2) |>
  lt_footnote("A note", "column", ~ x)
xfun::tojson(spec(x))
```
```
{
  "data": {
    "x": [1, 2],
    "y": [3, 4]
  },
  "ops": [
    {
      "type": "fmt_number",
      "columns": ["x"],
      "decimals": 2
    }
  ],
  "header": {
    "title": "Title",
    "subtitle": "Subtitle"
  },
  "spanners": [
    {
      "label": "Cols",
      "columns": ["x", "y"]
    }
  ],
  "footnotes": [
    {
      "text": "A note",
      "location": {
        "type": "column_labels",
        "columns": ["x"]
      }
    }
  ]
}
```

```r
d = data.frame(g = c("A", "A", "B"), v = 1:3)
x = lt(d) |> lt_group(~ g)
xfun::tojson(spec(x))
```
```
{
  "data": {
    "g": ["A", "A", "B"],
    "v": [1, 2, 3]
  },
  "row_group": ["g"]
}
```

```r
d = data.frame(a = 1:2, b = 3:4)
x = lt(d) |> lt_group("G1" = 1L, "G2" = 2L)
xfun::tojson(spec(x))
```
```
{
  "data": {
    "a": [1, 2],
    "b": [3, 4]
  },
  "ops": [
    {
      "type": "row_group",
      "label": "G1",
      "rows": [1]
    },
    {
      "type": "row_group",
      "label": "G2",
      "rows": [2]
    }
  ]
}
```

```r
d = data.frame(a = 1:2, b = 3:4, c = 5:6)
x = lt(d) |> lt_merge(~ a + b, pattern = "{1} ({2})")
xfun::tojson(spec(x))
```
```
{
  "data": {
    "a": [1, 2],
    "b": [3, 4],
    "c": [5, 6]
  },
  "ops": [
    {
      "type": "merge",
      "columns": ["a", "b"],
      "pattern": "{1} ({2})",
      "hide": true
    }
  ]
}
```

```r
d = data.frame(x = 1:2)
x = lt(d) |> lt_style("x", test = "v => v > 1", class = "hi")
xfun::tojson(spec(x))
```
```
{
  "data": {
    "x": [1, 2]
  },
  "ops": [
    {
      "type": "style",
      "columns": ["x"],
      "test": v => v > 1,
      "class": "hi"
    }
  ]
}
```
