library(testit)
if (tolower(Sys.getenv("CI")) == "true" && nzchar(Sys.which("node")))
  test_pkg("lt", "test-ci")
