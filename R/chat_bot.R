chat_bot <- function(system_prompt = NULL, default_turns = list()) {
  system_prompt <- system_prompt %||% databot_prompt()

  bedrock_model <- Sys.getenv("DATABOT_BEDROCK_MODEL", "")
  if (nzchar(bedrock_model)) {
    chat <- chat_aws_bedrock(
      system_prompt,
      model = bedrock_model,
      echo = FALSE
    )
  } else {

    api_key <- Sys.getenv("DATABOT_API_KEY", Sys.getenv("ANTHROPIC_API_KEY", ""))
    if (api_key == "") {
      abort(paste(
        "No API key found;",
        "please set DATABOT_API_KEY or ANTHROPIC_API_KEY env var"
      ))
    }

    chat <- chat_anthropic(
      system_prompt,
      model = "claude-3-5-sonnet-latest",
      echo = FALSE,
      api_key = api_key
    )
  }
  chat$set_turns(default_turns)
  
  chat$register_tool(tool(
    run_r_code,
    "Executes R code in the current session",
    arguments = list(
      code = type_string("R code to execute")
    )
  ))
  chat$register_tool(tool(
    create_quarto_report,
    "Creates a Quarto report and displays it to the user",
    arguments = list(
      filename = type_string(
        "The desired filename of the report. Should end in `.qmd`."
      ),
      content = type_string("The full content of the report, as a UTF-8 string.")
    )
  ))
  chat
}
