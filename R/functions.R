#' Evaluate R code and capture all outputs in a structured format
#' @param code Character string containing R code to evaluate
#' @return List containing structured output information
#' @noRd
evaluate_r_code <- function(
  code,
  on_console_out,
  on_console_err,
  on_plot,
  on_dataframe,
  on_tagifiable
) {
  cat("Running code...\n")
  cat(code, "\n", sep = "")

  # Evaluate the code and capture all outputs
  evaluate::evaluate(
    code,
    envir = globalenv(), # evaluate in the global environment
    stop_on_error = 1, # stop on first error
    output_handler = evaluate::new_output_handler(
      text = function(value) {
        on_console_out(as_str(value))
      },
      graphics = function(recorded_plot) {
        plot <- recorded_plot_to_png(recorded_plot)
        on_plot(plot$mime, plot$content)
      },
      message = function(cond) {
        on_console_out(as_str(conditionMessage(cond), "\n"))
      },
      warning = function(cond) {
        on_console_out(as_str("Warning: ", conditionMessage(cond), "\n"))
      },
      error = function(cond) {
        on_console_out(as_str("Error: ", conditionMessage(cond), "\n"))
      },
      value = function(value) {
        # Mostly to get ggplot2 to plot
        # Find the appropriate S3 method for `print` using class(value)
        if (is.data.frame(value)) {
          on_dataframe(value)
        } else if (is_shiny_tag(value)) {
          on_tagifiable(value)
        } else {
          printed_str <- as_str(utils::capture.output(print(value)))
          if (nchar(printed_str) > 0 && !grepl("\n$", printed_str)) {
            printed_str <- paste0(printed_str, "\n")
          }
          on_console_out(printed_str)
        }
      }
    )
  )
  invisible()
}

is_shiny_tag <- function(tag) {
  inherits(tag, c("shiny.tag", "shiny.tag.list", "htmlwidget"))
}


#' Save a recorded plot to base64 encoded PNG
#' 
#' @param recorded_plot Recorded plot to save
#' @param ... Additional arguments passed to [png()]
#' @noRd
recorded_plot_to_png <- function(recorded_plot, ...) {
  plot_file <- tempfile(fileext = ".png")
  on.exit(if (plot_file != "" && file.exists(plot_file)) unlink(plot_file))

  grDevices::png(plot_file, ...)
  tryCatch(
    {
      grDevices::replayPlot(recorded_plot)
    },
    finally = {
      grDevices::dev.off()
    }
  )
  
  # Convert the plot to base64
  plot_data <- base64enc::base64encode(plot_file)
  list(mime = "image/png", content = plot_data)
}

split_df <- function(n, show_start = 20, show_end = 10) {
  if (n <= show_start + show_end) {
    return(list(
      head = n,
      skip = 0,
      tail = 0
    ))
  } else {
    return(list(
      head = show_start,
      skip = n - show_start - show_end,
      tail = show_end
    ))
  }
}

encode_df_for_model <- function(df, max_rows = 20, show_end = 10) {
  if (nrow(df) == 0) {
    return(paste(collapse = "\n", utils::capture.output(print(tibble::as.tibble(df)))))
  }

  split <- split_df(nrow(df), show_start = max_rows, show_end = show_end)

  if (split$skip == 0) {
    return(df_to_json(df))
  }

  paste(collapse = "\n", c(
    df_to_json(head(df, split$head)),
    sprintf("... %d rows omitted ...", split$skip),
    df_to_json(tail(df, split$tail))
  ))
}

df_to_json <- function(df) {
  jsonlite::toJSON(df, dataframe = "rows", na = "string")
}
