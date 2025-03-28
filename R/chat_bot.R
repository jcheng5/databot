chat_bot <- function(system_prompt = NULL, default_turns = list()) {
  system_prompt <- system_prompt %||% databot_prompt()

  api_key <- Sys.getenv("DATABOT_API_KEY", Sys.getenv("ANTHROPIC_API_KEY", ""))
  if (api_key == "") {
    abort(paste(
      "No API key found;",
      "please set DATABOT_API_KEY or ANTHROPIC_API_KEY env var"
    ))
  }

  chat <- chat_claude(
    system_prompt,
    model = "claude-3-5-sonnet-latest",
    turns = default_turns,
    echo = FALSE,
    api_key = api_key
  )
  chat$register_tool(tool(
    run_r_code,
    "Executes R code in the current session",
    code = type_string("R code to execute")
  ))
  chat$register_tool(tool(
    create_quarto_report,
    "Creates a Quarto report and displays it to the user",
    filename = type_string(
      "The desired filename of the report. Should end in `.qmd`."
    ),
    content = type_string("The full content of the report, as a UTF-8 string.")
  ))
  chat
}
