.onLoad <- function(libname, pkgname) {
  # This function is called when the package is loaded
  # You can put any initialization code here if needed
  
  # Hack around specific limitation of ellmer. We need the ability to return
  # distinct content blocks from tool calls, so that the model can see images.
  # Ellmer currently (0.3.2) supports this only for the Anthropic provider, not
  # the Bedrock one.
  as_json <- ellmer:::as_json
  S7::method(as_json, list(ellmer:::ProviderAWSBedrock, ellmer:::ContentToolResult)) <- function(
    provider,
    x,
    ...
  ) {
    preserve_json <- inherits(x@value, "AsIs") || inherits(x@value, "json")
    if (preserve_json) {
      content <- x@value
    } else {
      content <- list(list(text = ellmer:::tool_string(x@value)))
    }
    str(content)
    
    list(
      toolResult = list(
        toolUseId = x@request@id,
        content = content,
        status = if (ellmer:::tool_errored(x)) "error" else "success"
      )
    )
  }
}
