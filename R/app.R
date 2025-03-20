#' @import shiny
#' @import bslib
#' @import ellmer
#' @import shinychat
NULL

html_deps <- function() {
  htmltools::htmlDependency(
    "databot",
    utils::packageVersion("databot"),
    src = "www",
    package = "databot",
    script = "script.js",
    stylesheet = "style.css"
  )
}

# I haven't looked into exactly why this is, but in order for htmlwidgets to work, 
# we need it's dependencies on the page. What's extra odd about this is that it 
# doesn't appear to be an issue for shinychat apps in general??
htmlwidget_deps <- function() {
  htmltools::findDependencies(htmlwidgets::shinyWidgetOutput("foo", "bar", NULL, NULL))
}

#' Runs databot
#' 
#' @export
chat <- function() {
  withr::local_envvar(NO_COLOR = "1")

  ui <- page_fillable(
    html_deps(),
    htmlwidgets_deps(),
    chat_ui("chat", fill = TRUE, height = "100%", width = "100%")
  )

  server <- function(input, output, session) {
    chat <- chat_bot()
    start_chat_request <- function(user_input) {
      stream <- chat$stream_async(user_input)
      promises::finally(chat_append("chat", stream), ~ {
        tokens <- chat$tokens(include_system_prompt = FALSE)
        input <- sum(tokens$tokens[tokens$role == "user"])
        output <- sum(tokens$tokens[tokens$role == "assistant"])

        cat("\n")
        cat(rule("Turn ", nrow(tokens) / 2), "\n", sep = "")
        cat("Total input tokens:  ", input, "\n", sep = "")
        cat("Total output tokens: ", output, "\n", sep = "")
        cat("Total tokens:        ", input + output, "\n", sep = "")
        cat("\n")
        last_chat <<- chat
      })
    }

    observeEvent(input$chat_user_input, {
      start_chat_request(input$chat_user_input)
    })

    # Kick start the chat session
    start_chat_request("Hello")
  }

  print(shinyApp(ui, server))
}
