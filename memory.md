# Databot Multi-Agent Architecture Design

The user provided the following request:


> Currently, databot uses one agent, who both communicates with the user (the "greeter") and executes code and interprets > analyses (the "coder"). This can be a bit overwhelming for the user, as the agent generates a lot of code and output, usually > far more than the user is able to interpret. I would like to split databot up into two (or more) agents.
> 
> * The greeter is the agent that databot talks to. The agent, very importantly, says very little and only surfaces the most > information-dense learnings from the coder.
> * The coder writes code, looks at the results, and decides what code to write next. We still want it to give up control > occasionally so that the user can interject. 
> 
> Important questions:
> 
> * How do the greeter and coder communicate? It _could_ be a "hook" inside of `run_r_code()`, it could be the file system, etc. > Consider both directions.
> * Should there be only one coder? Or should coders be "ephemeral" agents that are spawned every time a user sends a request to > the greeter?
> * Ultimately, we'd like insights from the coder to proliferate up to the user every time `run_r_code()` is invoked, based on the current conversation history and the code output, summarized down to less than a sentence. When plots are generated via R code, we probably want them to proliferate up automatically (and have the greeter or a summarizing agent caption the image > with a sentence.)
> * Currently, one main benefit of the current approach is verifiability; the user can see all of the code being streamed in and critique it as it does (as long as they can keep up). How can we preserve this verifiability? I think, ultimately, when > `run_r_code()` calls are summarized, we want users to be able to "click in" to the summaries and read the full source code.
> 
> Other considerations:
> 
>  1) For speed, I think it's important that both the greeter and the coder  receive requests at the same time. (Or the coder only—maybe the greeter doesn't even need to see it.)                      
> 2) I think `run_r_code()` should still just return the results as-is, but right before it returns it also has a hook to send the results to the greeter (or to a summarizer agent that has access to the UI). Onlythen would the summarizing happen—this way, the coder can just see the results of the code it ran and keep iterating, as it does currently.


## Overview

Split databot from one overwhelming agent into a cleaner multi-agent system:
- **Coder**: Autonomous code executor that iterates on analysis
- **Summarizer**: Digests code outputs into one-sentence insights
- **UI**: Progressive disclosure interface for verifiability

## Key Design Principles

1. **Parallel execution**: Coder starts immediately when user submits request
2. **Hook-based summarization**: `run_r_code()` triggers summarizer via async hook
3. **Non-blocking**: Summarizer runs in background, doesn't slow down coder
4. **Verifiability**: Full code/output available via expandable UI elements

## Architecture Flow

```
User Input
    ↓
    ├─→ Greeter (acknowledges only)
    │     ↓
    │   "Let me analyze this..."
    │
    └─→ Coder (via mirai)
          ↓
        run_r_code("analysis code")
          ↓
          ├─→ Returns raw results to Coder (immediate)
          │     ↓
          │   Coder continues iterating
          │
          └─→ Triggers Summarizer (async hook)
                ↓
              Summarizer analyzes output
                ↓
              Updates UI with insight
```

## Core Implementation

### 1. Parallel Request Handling

```r
# In app.R server function
observeEvent(input$chat_user_input, {
  user_input <- input$chat_user_input
  
  # Greeter just acknowledges immediately
  chat_append_message("chat", list(
    role = "assistant", 
    content = "Let me analyze this for you..."
  ))
  
  # Coder gets to work immediately in parallel
  coder_task <- ExtendedTask$new(function(input) {
    mirai({
      coder <- chat_anthropic(coder_prompt, echo = FALSE)
      coder$register_tool(tool(
        run_r_code,  # Still returns raw results to coder
        "Executes R code in the current session",
        arguments = list(code = type_string("R code to execute"))
      ))
      
      # Coder works autonomously
      coder$chat(input)
    })
  })
  
  coder_task$invoke(user_input)
})
```

### 2. Hook-Based Summarization in `run_r_code()`

```r
# Modified tools.R
run_r_code <- function(code) {
  # Existing code execution logic...
  result <- evaluate_r_code(code, ...)
  
  # NEW: Hook to summarizer agent (async, non-blocking)
  summarize(
    code = code,
    output = result,
    context = get_current_conversation_context()
  )
  
  # Return immediately to coder (unchanged behavior)
  I(result)
}

# New function to trigger summarizer
summarize <- function(code, output, context) {
  # This runs async via mirai, doesn't block the coder
  summarizer_task <- ExtendedTask$new(function(c, o, ctx) {
    mirai({
      summarizer <- chat_anthropic(
        system_prompt = "You are a concise data science summarizer. 
                        Summarize code outputs in one sentence or less.
                        For plots, provide a one-sentence caption.",
        echo = FALSE
      )
      
      summary <- summarizer$chat_structured(
        paste("Summarize this output:", o),
        type = type_object(
          insight = type_string("One sentence summary"),
          plot_caption = type_string("Caption if plot exists, else null"),
          importance = type_enum("high", "medium", "low")
        )
      )
      
      summary
    })
  })
  
  # Fire and forget - results handled via promise
  summarizer_task$invoke(code, output, context) %...>% {
    # When summary is ready, update UI
    update_message_with_summary(.)
  }
}
```

### 3. Progressive Disclosure UI

```r
# Helper to update existing message with summary
update_message_with_summary <- function(summary) {
  # Create collapsible UI element
  summary_ui <- tagList(
    div(class = "summary-insight",
      icon("lightbulb"),
      span(summary$insight)
    ),
    if (!is.null(summary$plot_caption)) {
      p(class = "plot-caption", summary$plot_caption)
    },
    # Collapsible details with original code/output
    details(
      summary("View code and full output"),
      pre(class = "code-block", summary$code),
      pre(class = "output-block", summary$output)
    )
  )
  
  # Append to chat (or update last message)
  chat_append_message("chat", list(
    role = "assistant",
    content = summary_ui
  ))
}
```

## Implementation Steps

### Phase 1: Hook Infrastructure

1. **Modify `run_r_code()` in tools.R**
   ```r
   run_r_code_with_hooks <- function(code) {
     # Store context for summarizer
     store_execution_context(code)
     
     # Execute normally
     result <- run_r_code(code)
     
     # Trigger async summarization
     spawn_summarizer(code, result)
     
     # Return immediately to coder
     result
   }
   ```

2. **Create summarizer spawning logic**
   ```r
   spawn_summarizer <- function(code, result) {
     # Don't block - use promises
     promises::promise(function(resolve, reject) {
       m <- mirai({
         # Summarize in background
         create_summary(code, result)
       })
       resolve(m)
     }) %...>% {
       # Update UI when ready
       append_summary_to_chat(.)
     }
   }
   ```

### Phase 2: Agent System

1. **Update `chat_bot()` to register enhanced tool**
   ```r
   chat_bot <- function(system_prompt = NULL, default_turns = list()) {
     # ... existing code ...
     
     # Register hook-enabled run_r_code
     chat$register_tool(tool(
       run_r_code_with_hooks,  # New wrapper function
       "Executes R code in the current session",
       arguments = list(code = type_string("R code to execute"))
     ))
   }
   ```

2. **Implement parallel agent spawning in app.R**

### Phase 3: UI Enhancements

1. **Add expandable details components**
   - Use `bslib::accordion()` or custom `details/summary` tags
   - Store full outputs in reactive values indexed by message ID
   - Add "expand/collapse all" controls

2. **Style summary components**
   ```css
   .summary-insight {
     padding: 8px 12px;
     background: #f0f8ff;
     border-left: 3px solid #2196f3;
     margin: 8px 0;
   }
   
   .plot-caption {
     font-style: italic;
     color: #666;
     margin-top: 4px;
   }
   
   details {
     margin-top: 8px;
     border: 1px solid #ddd;
     border-radius: 4px;
   }
   
   summary {
     padding: 8px;
     background: #f9f9f9;
     cursor: pointer;
   }
   ```

## Benefits

- **Speed**: Coder starts immediately, no waiting for greeter
- **Clarity**: Users see condensed insights, not overwhelming code dumps
- **Verifiability**: All code/output accessible via progressive disclosure
- **Scalability**: Can spawn multiple agents as needed
- **Non-blocking**: Summarization doesn't slow down analysis
- **Better UX**: Clean interface with details on demand

## Technical Notes

- Use **mirai** for parallel agent execution
- Use **ExtendedTask** for async Shiny integration
- Use **promises** for non-blocking UI updates
- Maintain existing `run_r_code()` contract for coder
- Add hook system that doesn't break existing functionality

## Future Enhancements

- **Multiple coders**: Spawn specialized coders for different analysis types
- **Smart routing**: Direct different question types to appropriate agents  
- **Context awareness**: Summarizer understands full conversation history
- **Interactive summaries**: Let users refine or expand insights
- **Caching**: Avoid re-summarizing identical code outputs
