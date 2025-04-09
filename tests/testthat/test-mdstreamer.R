test_that("MarkdownStreamer constructor validates inputs", {
  # Valid callback
  expect_no_error(MarkdownStreamer$new(function(x) NULL))
  
  # Not a function
  expect_error(MarkdownStreamer$new("not a function"), "must be a function")
  
  # Function with wrong number of arguments
  expect_error(MarkdownStreamer$new(function() NULL), "exactly one argument")
  expect_error(MarkdownStreamer$new(function(x, y) NULL), "exactly one argument")
})

test_that("code() validates inputs", {
  ms <- MarkdownStreamer$new(function(x) NULL)
  expect_error(ms$code(1), "must be a character vector")
})

test_that("md() accepts character vectors of length > 1", {
  output <- ""
  ms <- MarkdownStreamer$new(function(x) output <<- paste0(output, x))
  
  ms$md(c("Line 1", "Line 2", "Line 3"))
  
  expect_equal(output, "Line 1\nLine 2\nLine 3")
})

test_that("code() accepts character vectors of length > 1", {
  output <- ""
  ms <- MarkdownStreamer$new(function(x) output <<- paste0(output, x))
  
  ms$code(c("def hello():", "    print('Hello')", "    return True"))
  
  expect_equal(output, "\n``````\ndef hello():\n    print('Hello')\n    return True")
})

test_that("empty strings are a no-op regardless of vector length", {
  output <- ""
  ms <- MarkdownStreamer$new(function(x) output <<- paste0(output, x))
  
  ms$md("")
  ms$code("")
  ms$md(c("", ""))
  ms$code(c("", "", ""))
  
  expect_equal(output, "")
})

test_that("md() outputs text correctly", {
  output <- ""
  ms <- MarkdownStreamer$new(function(x) output <<- paste0(output, x))
  
  ms$md("Hello, world!")
  
  expect_equal(output, "Hello, world!")
})

test_that("code() formats code blocks correctly", {
  output <- ""
  ms <- MarkdownStreamer$new(function(x) output <<- paste0(output, x))
  
  ms$code("print('hello')")
  
  expect_equal(output, "\n``````\nprint('hello')")
})

test_that("consecutive code() calls result in one code block", {
  output <- ""
  ms <- MarkdownStreamer$new(function(x) output <<- paste0(output, x))
  
  ms$code("line 1")
  ms$code("line 2")
  
  expect_equal(output, "\n``````\nline 1line 2")
})

test_that("code blocks get closed when switching to md()", {
  output <- ""
  ms <- MarkdownStreamer$new(function(x) output <<- paste0(output, x))
  
  ms$code("code")
  ms$md("text")
  
  expect_equal(output, "\n``````\ncode\n``````\ntext")
})

test_that("close() closes code blocks", {
  output <- ""
  ms <- MarkdownStreamer$new(function(x) output <<- paste0(output, x))
  
  ms$code("code")
  ms$close()
  
  expect_equal(output, "\n``````\ncode\n``````\n")
})

test_that("ensure_newline_before adds newlines when needed", {
  output <- ""
  ms <- MarkdownStreamer$new(function(x) output <<- paste0(output, x))
  
  ms$md("no newline")
  ms$md("needs newline", ensure_newline_before = TRUE)
  
  expect_equal(output, "no newline\nneeds newline")
})

test_that("ensure_newline_after adds newlines when needed", {
  output <- ""
  ms <- MarkdownStreamer$new(function(x) output <<- paste0(output, x))
  
  ms$md("text", ensure_newline_after = TRUE)
  
  expect_equal(output, "text\n")
})

test_that("text already ending with newline doesn't get duplicate newlines", {
  output <- ""
  ms <- MarkdownStreamer$new(function(x) output <<- paste0(output, x))
  
  ms$md("text\n", ensure_newline_after = TRUE)
  
  expect_equal(output, "text\n")
})

test_that("text already starting with newline doesn't get duplicate newlines", {
  output <- ""
  ms <- MarkdownStreamer$new(function(x) output <<- paste0(output, x))
  
  ms$md("text")
  ms$md("\nmore text", ensure_newline_before = TRUE)
  
  expect_equal(output, "text\nmore text")
})

test_that("chaining works", {
  output <- ""
  ms <- MarkdownStreamer$new(function(x) output <<- paste0(output, x))
  
  ms$md("text")$code("code")$md("more text")
  
  expect_equal(output, "text\n``````\ncode\n``````\nmore text")
})
