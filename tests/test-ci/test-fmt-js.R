# Number and date formatting: fmt_number (decimals, significant digits,
# percent, big_mark, minus sign, prefix/suffix, infinity), auto-format, fmt_date.

assert("fmt_number formats decimals", {
  html = build(list(
    data = list(x = c(1.1, 2.346)),
    ops = list(list(type = "fmt_number", columns = list("x"), decimals = 2))
  ))
  (matches(html, ".*>1\\.10</td>.*>2\\.35</td>.*") %==% "")
})

assert("fmt_number formats significant digits across magnitudes", {
  # 3 sig figs: values spanning orders of magnitude each keep 3 meaningful
  # digits (small values gain decimals, large ones lose them).
  html = build(list(
    data = list(x = c(0.0042857, 4285.7)),
    ops = list(list(type = "fmt_number", columns = list("x"), sig_digits = 3))
  ))
  (matches(html, ".*>0\\.00429</td>.*>4290</td>.*") %==% "")
  # toPrecision would render 4290 as "4.29e+3"; it is expanded to plain
  # decimal, and big_mark still applies to the integer part.
  html = build(list(
    data = list(x = 4285.7),
    ops = list(list(type = "fmt_number", columns = list("x"),
                    sig_digits = 2, big_mark = ","))
  ))
  (matches(html, ".*>4,300</td>.*") %==% "")
  # Negative small value uses the typographic minus (U+2212).
  html = build(list(
    data = list(x = -0.0042857),
    ops = list(list(type = "fmt_number", columns = list("x"), sig_digits = 2))
  ))
  (matches(html, ".*>−0\\.0043</td>.*") %==% "")
})

assert("auto-format picks decimals from value width", {
  # Small values (<1) get up to 4 decimals; the big_mark separator is a
  # non-breaking space (U+00A0).
  html = build(list(data = list(x = c(0.123456, 0.987))))
  (matches(html, ".*>0\\.1235</td>.*>0\\.9870</td>.*") %==% "")
  # Large values are rounded to 0 decimals and grouped.
  html = build(list(data = list(x = c(1234.5, 9999.9))))
  (matches(html, ".*>1 235</td>.*>10 000</td>.*") %==% "")
})

assert("auto_format = FALSE leaves numbers untouched", {
  html = build(list(data = list(x = c(1.23456, 2.34567)), auto_format = FALSE))
  (matches(html, ".*>1\\.23456</td>.*>2\\.34567</td>.*") %==% "")
})

assert("fmt_number with percent, big_mark, and minus sign", {
  html = build(list(
    data = list(x = c(0.1234, 12345.678)),
    ops = list(list(type = "fmt_number", columns = list("x"),
                    percent = TRUE, decimals = 1, big_mark = ","))
  ))
  (matches(html, ".*>12\\.3%</td>.*>1,234,567\\.8%</td>.*") %==% "")
  # Negative numbers render with a real minus sign (U+2212), not a hyphen.
  html = build(list(
    data = list(n = -1234567),
    ops = list(list(type = "fmt_number", columns = list("n"), big_mark = ","))
  ))
  (matches(html, ".*>−1,234,567</td>.*") %==% "")
})

assert("infinity renders as ∞, with minus sign depending on formatting", {
  # Raw (unformatted, non-numeric column) infinities use an ASCII hyphen.
  html = build(list(data = list(x = c(Inf, -Inf)), auto_format = FALSE))
  (matches(html, ".*>∞</td>.*>-∞</td>.*") %==% "")
  # Auto-formatted numeric column: minus becomes the typographic minus (U+2212).
  html = build(list(data = list(x = c(1.5, Inf, -Inf))))
  (matches(html, ".*>∞</td>.*>−∞</td>.*") %==% "")
  # Explicit fmt_number keeps ±∞ and uses the typographic minus.
  html = build(list(
    data = list(x = c(Inf, -Inf)),
    ops = list(list(type = "fmt_number", columns = list("x"), decimals = 2))
  ))
  (matches(html, ".*>∞</td>.*>−∞</td>.*") %==% "")
})

assert("fmt_number prefix and suffix", {
  html = build(list(
    data = list(price = c(1234.5, 678.9)),
    ops = list(list(
      type = "fmt_number", columns = list("price"),
      decimals = 2, big_mark = ",", prefix = "$"
    ))
  ))
  (matches(html, '.*>\\$1,234\\.50</td>.*>\\$678\\.90</td>.*') %==% "")
  # suffix
  html = build(list(
    data = list(weight = c(75, 80)),
    ops = list(list(
      type = "fmt_number", columns = list("weight"), suffix = " kg"
    ))
  ))
  (matches(html, '.*>75 kg</td>.*>80 kg</td>.*') %==% "")
  # prefix + percent
  html = build(list(
    data = list(rate = c(0.05, 0.12)),
    ops = list(list(
      type = "fmt_number", columns = list("rate"),
      decimals = 1, percent = TRUE, prefix = "+"
    ))
  ))
  (matches(html, '.*>\\+5\\.0%</td>.*>\\+12\\.0%</td>.*') %==% "")
})

assert("fmt_date formats ISO date strings", {
  html = build(list(
    data = list(event = c("A", "B"), date = c("2024-01-15", "2024-06-30")),
    ops = list(list(type = "fmt_date", columns = list("date"), method = "toISOString"))
  ))
  (matches(html, '.*>2024-01-15T00:00:00\\.000Z</td>.*>2024-06-30T00:00:00\\.000Z</td>.*') %==% "")
  # toUTCString
  html = build(list(
    data = list(date = "2024-01-15"),
    ops = list(list(type = "fmt_date", columns = list("date"), method = "toUTCString"))
  ))
  (matches(html, '.*>Mon, 15 Jan 2024 00:00:00 GMT</td>.*') %==% "")
  # null values are skipped by fmt_date; the em dash comes from the missing
  # default injected on the render path (see with_missing()).
  html = build(list(
    data = list(date = list("2024-01-15", NULL)),
    ops = list(list(type = "fmt_date", columns = list("date"), method = "toISOString"))
  ))
  (matches(html, '.*>2024-01-15T00:00:00\\.000Z</td>.*>—</td>.*') %==% "")
})
