#' @import shiny
#' @import bslib
#' @import ellmer
#' @import shinychat
#' @importFrom utils head tail
NULL

html_deps <- function() {
  htmltools::htmlDependency(
    "databot",
    utils::packageVersion("databot"),
    src = "www",
    package = "databot",
    stylesheet = "style.css"
  )
}

latest_session <- reactiveVal()

#' Runs databot
#'
#' @param new_session Logical. If `TRUE`, starts a new chat session. If `FALSE`
#'   (the default), restores the previous chat session (only within the current
#'   R process).
#'
#' @export
chat <- function(new_session = FALSE) {
  withr::local_envvar(NO_COLOR = "1")

  if (isTRUE(new_session)) {
    reset_state()
  }

  ui <- page_fillable(
    html_deps(),
    chat_ui("chat", fill = TRUE, height = "100%", width = "100%")
  )

  server <- function(input, output, session) {
    session$allowReconnect(TRUE)
    latest_session(session$token)
    observe({
      if (!identical(latest_session(), session$token)) {
        showModal(modalDialog(
          "Your session ended because a new session was started in a ",
          "different browser tab.",
          fade = FALSE,
          easyClose = TRUE
        ))
        session$close()
      }
    })

    restored_since_last_turn <- FALSE

    # Restore previous chat session, if applicable
    if (globals$ui_messages$size() > 0) {
      ui_msgs <- globals$ui_messages$as_list()
      if (identical(ui_msgs[[1]], list(role = "user", content = "Hello"))) {
        ui_msgs <- ui_msgs[-1]
      }
      for (msg in ui_msgs) {
        chat_append_message("chat", msg, chunk = FALSE)
      }
      restored_since_last_turn <- TRUE
    }

    chat <- chat_bot(default_turns = globals$turns)
    start_chat_request <- function(user_input) {
      # For local debugging
      if (interactive()) {
        globals$last_chat <- chat
      }

      prefix <- if (restored_since_last_turn) {
        paste0(
          "(Continuing previous chat session. The R environment may have ",
          "changed since the last request/response.)\n\n"
        )
      } else {
        ""
      }
      restored_since_last_turn <<- FALSE

      stream <- save_stream_output()(
        chat$stream_async(paste0(prefix, user_input))
      )
      chat_append("chat", stream) |>
        promises::then(
          ~ {
            if (session$isClosed()) {
              req(FALSE)
            }

            # After each successful turn, save everything in case we need to
            # restore (i.e. user stops the app and restarts it)
            globals$turns <- chat$get_turns()
            save_messages(
              list(role = "user", content = user_input),
              list(role = "assistant", content = take_pending_output())
            )
          }
        ) |>
        promises::finally(
          ~ {
            tokens <- chat$get_tokens()
            last_input <- tail(tokens[tokens$role == "user", "tokens_total"], 1)
            last_output <- tail(tokens[tokens$role == "assistant", "tokens_total"], 1)
            total_input <- sum(tokens[tokens$role == "user", "tokens_total"])
            total_output <- sum(tokens[tokens$role == "assistant", "tokens_total"])

            cat("\n")
            cat(rule("Turn ", nrow(tokens)), "\n", sep = "")
            cat("Input tokens:  ", last_input, "\n", sep = "")
            cat("Output tokens: ", last_output, "\n", sep = "")
            cat("Total input tokens:  ", total_input, "\n", sep = "")
            cat("Total output tokens: ", total_output, "\n", sep = "")
            cat("\n")
          }
        )
    }

    observeEvent(input$chat_user_input, {
      start_chat_request(input$chat_user_input)
    })

    # Kick start the chat session (unless we've restored a previous session)
    if (length(chat$get_turns()) == 0) {
      start_chat_request("Hello")
    }
  }

  print(shinyApp(ui, server))
}

globals <- new.env(parent = emptyenv())
globals$turns <- NULL
globals$ui_messages <- fastmap::fastqueue()
globals$pending_output <- fastmap::fastqueue()
globals$last_chat <- NULL

reset_state <- function() {
  globals$turns <- NULL
  globals$ui_messages$reset()
  globals$pending_output$reset()
  invisible()
}

save_messages <- function(...) {
  for (msg in list(...)) {
    globals$ui_messages$add(msg)
  }
  invisible()
}

save_output_chunk <- function(chunk) {
  globals$pending_output$add(chunk)
  invisible()
}

take_pending_output <- function() {
  chunks <- unlist(globals$pending_output$as_list())
  globals$pending_output$reset()
  paste(collapse = "", chunks)
}

# Stream decorator that saves each chunk to pending_output
save_stream_output <- function() {
  coro::async_generator(function(stream) {
    session <- getDefaultReactiveDomain()
    buffer <- ""
    in_insight <- FALSE
    insight_content <- ""
    
    for (chunk in coro::await_each(stream)) {
      if (session$isClosed()) {
        req(FALSE)
      }
      save_output_chunk(chunk)
      
      buffer <- paste0(buffer, chunk)
      
      while (nchar(buffer) > 0) {
        if (!in_insight) {
          if (grepl("<insight>", buffer)) {
            match <- regexpr("<insight>", buffer)
            before <- substr(buffer, 1, match[1] - 1)
            
            if (nchar(before) > 0) {
              coro::yield(before)
            }
            
            coro::yield('<div class="summary-insight"><span>')
            
            buffer <- substr(buffer, match[1] + 9, nchar(buffer))
            in_insight <- TRUE
            insight_content <- ""
          } else {
            if (nchar(buffer) > 0) {
              coro::yield(buffer)
            }
            buffer <- ""
          }
        } else {
          if (grepl("</insight>", buffer)) {
            match <- regexpr("</insight>", buffer)
            content_before_close <- substr(buffer, 1, match[1] - 1)
            
            if (nchar(content_before_close) > 0) {
              coro::yield(content_before_close)
            }
            
            coro::yield('</span></div>')
            
            buffer <- substr(buffer, match[1] + 10, nchar(buffer))
            in_insight <- FALSE
          } else {
            if (nchar(buffer) > 0) {
              coro::yield(buffer)
            }
            buffer <- ""
          }
        }
      }
    }
    
    if (nchar(buffer) > 0) {
      coro::yield(buffer)
    }
    
    if (in_insight) {
      coro::yield('</span></div>')
    }
  })
}

last_chat <- function() {
  globals$last_chat
}