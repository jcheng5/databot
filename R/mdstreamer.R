MarkdownStreamer <- R6::R6Class("MarkdownStreamer",
  public = list(
    #' @description
    #' Create a new MarkdownStreamer object
    #' @param callback Function to process Markdown output, takes a single markdown argument
    initialize = function(callback) {
      if (!is.function(callback)) {
        abort("`callback` must be a function")
      }
      if (length(formals(callback)) != 1) {
        abort("`callback` must accept exactly one argument")
      }
      private$callback <- callback
      private$in_code_block <- FALSE
      private$last_ends_with_newline <- TRUE
      private$empty <- TRUE
    },
    
    #' @description
    #' Process text as regular Markdown
    #' @param text Text to be processed as Markdown, can be a character vector
    #' @param ensure_newline_before Ensure text starts with a newline
    #' @param ensure_newline_after Ensure text ends with a newline
    md = function(text, ensure_newline_before = FALSE, ensure_newline_after = FALSE) {
      # Validate inputs
      if (is.character(text)) {
          # Skip empty text
          if (length(text) == 0 || all(text == "")) {
            return(invisible(self))
          }
    
          # Collapse multi-line text
          if (length(text) > 1) {
            text <- paste(text, collapse = "\n")
          }
      }
      
      # Close code block if needed
      if (private$in_code_block) {
        private$close_code_block()
      }
      
      # Send the text with newline control
      private$send(text, ensure_newline_before, ensure_newline_after)
      
      invisible(self)
    },
    
    #' @description
    #' Process text as code block
    #' @param text Text to be formatted as a code block, can be a character vector
    #' @param ensure_newline_before Ensure a newline before the code block
    #' @param ensure_newline_after Ensure a newline after the code block
    code = function(text, ensure_newline_before = FALSE, ensure_newline_after = FALSE) {
      # Validate inputs
      if (!is.character(text)) {
        abort("`text` must be a character vector")
      }
      
      # Skip empty text
      if (length(text) == 0 || all(text == "")) {
        return(invisible(self))
      }
      
      # Collapse multi-line text
      if (length(text) > 1) {
        text <- paste(text, collapse = "\n")
      }
      
      # Start code block if needed with proper spacing
      if (!private$in_code_block) {
        private$send(as_str(
          # Make sure to double-newline from previous content. The leading "\n"
          # is one, while private$send(ensure_newline_before=TRUE) provides the
          # other.
          "\n```\n"
        ), TRUE, FALSE)
        private$in_code_block <- TRUE
      }
      
      # Add the text without additional markers
      private$send(text, ensure_newline_before, ensure_newline_after)
      
      invisible(self)
    },
    
    #' @description
    #' Close any open code blocks
    close = function() {
      if (private$in_code_block) {
        private$close_code_block()
      }
      invisible(self)
    }
  ),
  
  private = list(
    callback = NULL,
    in_code_block = FALSE,
    last_ends_with_newline = TRUE,
    empty = TRUE,
    
    #' @description
    #' Send text to the callback and update state
    #' @param text Text to send
    #' @param ensure_newline_before Ensure text starts with a newline
    #' @param ensure_newline_after Ensure text ends with a newline
    send = function(text, ensure_newline_before = FALSE, ensure_newline_after = FALSE) {
      if (!is.character(text)) {
        private$callback(text)
        if (private$empty) {
          private$empty <- FALSE
        }
        return()
      }
      # Check if text begins with a newline
      text_begins_with_newline <- grepl("^\n", text)
      
      # Add leading newline if needed and text doesn't already start with one
      if (ensure_newline_before && !private$last_ends_with_newline && !text_begins_with_newline) {
        private$callback("\n")
        private$last_ends_with_newline <- TRUE
      }
      
      # Send the main text
      private$callback(text)
      private$last_ends_with_newline <- grepl("\n$", text)
      
      # Add trailing newline if needed
      if (ensure_newline_after && !private$last_ends_with_newline) {
        private$callback("\n")
        private$last_ends_with_newline <- TRUE
      }

      if (private$empty) {
        private$empty <- FALSE
      }
    },
    
    #' @description
    #' Close a code block with proper formatting
    close_code_block = function() {
      private$send("```\n", TRUE, FALSE)
      private$in_code_block <- FALSE
    }
  )
)

NullStreamer <- R6::R6Class("MarkdownStreamer", public = list(
  md = function(text, ...) {
    invisible(self)
  },
  code = function(text, ... ) {
    invisible(self)
  },
  close = function() {
  }
))
