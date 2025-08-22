# Creates a Quarto report and displays it to the user
#
# @param filename The desired filename of the report. Should end in `.qmd`.
# @param content The full content of the report, as a UTF-8 string.
create_quarto_report <- function(filename, content) {
  dir.create(here::here("reports"), showWarnings = FALSE)
  dest <- file.path("reports", basename(filename))
  # TODO: Ensure UTF-8 encoding, even on Windows
  writeLines(content, dest)
  message("Saved report to ", dest)
  system2("quarto", c("render", dest))
  # change extension to .html
  rendered <- paste0(tools::file_path_sans_ext(dest), ".html")
  if (file.exists(rendered)) {
    message("Opening report in browser...")
    utils::browseURL(rendered)
  }
  invisible(NULL)
}

# Executes R code in the current session
#
# @param code R code to execute
# @param _intent Brief description of what the code does
# @returns The results of the evaluation
# @noRd
run_r_code <- function(code, `_intent` = "View code and full output") {
  # Try hard to suppress ANSI terminal formatting characters
  withr::local_envvar(NO_COLOR = 1)
  withr::local_options(rlib_interactive = FALSE, rlang_interactive = FALSE)

  markdown_output <- character()
  
  out <- MarkdownStreamer$new(function(md_text) {
    markdown_output <<- c(markdown_output, md_text)
  })
  on.exit({
    out$close()
    
    if (in_shiny() && length(markdown_output) > 0) {
      formatted_output <- htmltools::tagList(
        htmltools::tags$details(
          htmltools::tags$summary(`_intent`),
          htmltools::HTML(paste(markdown_output, collapse = ""))
        )
      )
      
      chat_append_message("chat", list(
        role = "assistant",
        content = as.character(formatted_output)
      ))
    }
  }, add = TRUE, after = FALSE)

  # What gets returned to the LLM
  result <- list()

  out_img <- function(media_type, b64data) {
    result <<- c(
      result,
      list(list(
        type = "image",
        source = list(
          type = "base64",
          media_type = media_type,
          data = b64data
        )
      ))
    )
    out$md(
      sprintf("![Plot](data:%s;base64,%s)\n\n", media_type, b64data),
      TRUE,
      FALSE
    )
  }

  out_df <- function(df) {
    ROWS_START <- 20
    ROWS_END <- 10

    # For the model
    df_json <- encode_df_for_model(
      df,
      max_rows = ROWS_START,
      show_end = ROWS_END
    )
    result <<- c(result, list(list(type = "text", text = df_json)))
    # For human
    # Make sure human sees same EXACT rows as model, this includes omitting the same rows
    split <- split_df(nrow(df), show_start = ROWS_START, show_end = ROWS_END)
    attrs <- "class=\"data-frame table table-sm table-striped\""
    md_tbl <- paste0(
      collapse = "\n",
      knitr::kable(head(df, split$head), format = "html", table.attr = attrs)
    )
    if (split$skip > 0) {
      md_tbl_skip <- sprintf("... %d rows omitted ...", split$skip)
      md_tbl_tail <- knitr::kable(
        tail(df, split$tail),
        format = "html",
        table.attr = attrs
      )
      md_tbl <- as_str(md_tbl, md_tbl_skip, md_tbl_tail)
    }
    out$md(md_tbl, TRUE, TRUE)
  }

  out_txt <- function(txt, end = NULL) {
    txt <- paste(txt, collapse = "\n")
    if (txt == "") {
      return()
    }
    if (!is.null(end)) {
      txt <- paste0(txt, end)
    }
    result <<- c(result, list(list(type = "text", text = txt)))
    out$code(txt)
  }

  out$code(code)
  # End the source code block so the outputs all appear in a separate block
  out$close()

  # Use the new evaluate_r_code function
  if (in_shiny()) {
    shiny::withLogErrors({
      evaluate_r_code(
        code,
        on_console_out = out_txt,
        on_console_err = out_txt,
        on_plot = out_img,
        on_dataframe = out_df
      )
    })
  } else {
    evaluate_r_code(
      code,
      on_console_out = out_txt,
      on_console_err = out_txt,
      on_plot = out_img,
      on_dataframe = out_df
    )
  }

  result <- coalesce_text_outputs(result)
  
  I(result)
}

in_shiny <- function() {
  !is.null(shiny::getDefaultReactiveDomain())
}

coalesce_text_outputs <- function(content_list) {
  txt_buffer <- character(0)
  result_content_list <- list()

  flush_buffer <- function() {
    if (length(txt_buffer) > 0) {
      result_content_list <<- c(
        result_content_list,
        list(list(type = "text", text = paste(txt_buffer, collapse = "\n")))
      )
      txt_buffer <<- character(0)
    }
  }

  for (content in content_list) {
    if (content[["type"]] == "text") {
      if (nzchar(content[["text"]])) {
        txt_buffer <- c(txt_buffer, content[["text"]])
      }
    } else {
      flush_buffer()
      result_content_list <- c(result_content_list, list(content))
    }
  }
  if (length(txt_buffer) > 0) {
    flush_buffer()
  }

  result_content_list
}
