d = data.frame(x = 1:3, y = c("b", "a", "c"))

assert("lt_interactive() records interactivity options on the spec", {
  x = lt(d) |> lt_interactive()
  (is.list(x$interactive))
  (x$interactive$sort %==% TRUE)
  (x$interactive$search %==% TRUE)
  # options are respected
  x2 = lt(d) |> lt_interactive(sort = FALSE, search = FALSE)
  (x2$interactive$sort %==% FALSE)
  (x2$interactive$search %==% FALSE)
})

assert("the interactive option is serialized into the spec block", {
  html = format(lt(d) |> lt_interactive())
  # the spec carries an `interactive` object read by the runtime
  (grepl('"interactive":', html) %==% TRUE)
})

assert("a non-interactive table records nothing and omits the extension", {
  x = lt(d)
  (is.null(x$interactive))
  html = format(x)
  # `lt-interactive` also appears in a core lt.js comment, so test for markers
  # unique to the extension itself
  (grepl('LT\\.plugins\\.interactive', html) %==% FALSE)
  (grepl('lti-search', html) %==% FALSE)
})

assert("format() inlines the interactive extension only when enabled", {
  html = format(lt(d) |> lt_interactive())
  (grepl('LT\\.plugins\\.interactive', html) %==% TRUE)  # js present
  (grepl('lti-search', html) %==% TRUE)                  # css present
})

assert("format(inline_assets = FALSE) links the interactive extension", {
  html = format(lt(d) |> lt_interactive(), inline_assets = FALSE)
  (grepl('<script src="[^"]*lt-interactive[^"]*" defer></script>', html) %==% TRUE)
  (grepl('<link rel="stylesheet" href="[^"]*lt-interactive[^"]*">', html) %==% TRUE)
})

assert("interactive_assets = FALSE suppresses the extension even when enabled", {
  html = format(lt(d) |> lt_interactive(), interactive_assets = FALSE)
  (grepl('LT\\.plugins\\.interactive', html) %==% FALSE)
  (grepl('lti-search', html) %==% FALSE)
})

assert("record_print emits the linked extension for an interactive table", {
  rec = record_print.lt_tbl(lt(d) |> lt_interactive())
  html = paste(unlist(rec), collapse = '\n')
  (grepl('lt-interactive', html) %==% TRUE)
  # a non-interactive table's record has no extension tags
  rec2 = record_print.lt_tbl(lt(d))
  (grepl('lt-interactive', paste(unlist(rec2), collapse = '\n')) %==% FALSE)
})
