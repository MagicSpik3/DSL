# Conservative parser for plain-text survey specifications.

slugify <- function(text) {
  value <- gsub("[^a-z0-9]+", "_", tolower(text))
  value <- gsub("(^_|_$)", "", value)
  if (!nzchar(value)) "question" else value
}

question_type <- function(prompt, choices) {
  lower_prompt <- tolower(prompt)
  if (length(choices) == 2L && all(grepl("^(yes|no)$", tolower(choices)))) return("boolean")
  if (length(choices)) return("choice")
  if (grepl("percentage|percent|amount|value|expenditure|income|turnover|cost|figures|how many|number", lower_prompt)) {
    return("number")
  }
  if (grepl("date|period", lower_prompt)) return("date")
  if (grepl("details|explain|comments", lower_prompt)) return("text")
  "unknown"
}

parse_survey_text <- function(path) {
  lines <- readLines(path, warn = FALSE, encoding = "UTF-8")
  lines <- gsub("\\r$", "", lines)
  trimmed <- trimws(lines)
  sections <- list()
  questions <- list()
  current_section <- NULL
  current_question <- NULL

  finish_question <- function() {
    if (is.null(current_question)) return()
    question <- current_question
    if (is.null(question$choices) || !length(question$choices)) question$choices <- character()
    question$type <- question_type(question$prompt, question$choices)
    question$guidance <- trimws(paste(question$guidance, collapse = " "))
    questions[[length(questions) + 1L]] <<- question
    current_question <<- NULL
  }

  for (line_number in seq_along(trimmed)) {
    line <- trimmed[[line_number]]
    if (!nzchar(line)) next
    section_match <- regexec("^Section[[:space:]]+([A-Z]):[[:space:]]*(.+)$", line, ignore.case = TRUE)
    section_parts <- regmatches(line, section_match)[[1L]]
    if (length(section_parts)) {
      finish_question()
      current_section <- list(id = tolower(section_parts[[2L]]), title = section_parts[[3L]])
      sections[[length(sections) + 1L]] <- c(current_section, list(source_line = line_number))
      next
    }

    option_match <- regexec("^[a-z][)]?[[:space:]]+(.+)$", line, ignore.case = TRUE)
    option_parts <- regmatches(line, option_match)[[1L]]
    if (length(option_parts) && !is.null(current_question)) {
      current_question$choices <- c(current_question$choices, option_parts[[2L]])
      next
    }

    is_question <- grepl("\\?[[:space:]]*$", line)
    if (is_question) {
      finish_question()
      current_question <- list(
        prompt = line,
        section = if (is.null(current_section)) "unsectioned" else current_section$id,
        source_line = line_number,
        guidance = character(),
        choices = character(),
        review = character()
      )
    } else if (!is.null(current_question)) {
      current_question$guidance <- c(current_question$guidance, line)
      if (grepl("if you answer|alternatively|only traded|exclude|include", tolower(line))) {
        current_question$review <- c(current_question$review, line)
      }
    }
  }
  finish_question()

  ids <- vapply(questions, function(question) slugify(question$prompt), character(1))
  duplicates <- duplicated(ids) | duplicated(ids, fromLast = TRUE)
  ids[duplicates] <- make.unique(ids[duplicates], sep = "_")
  for (index in seq_along(questions)) {
    questions[[index]]$id <- ids[[index]]
    questions[[index]]$depends_on <- if (index > 1L && length(questions[[index - 1L]]$review) &&
      any(grepl("if you answer yes|if you answer no", tolower(questions[[index - 1L]]$review)))) {
      questions[[index - 1L]]$id
    } else NULL
  }
  structure(list(path = path, sections = sections, questions = questions), class = "parsed_survey")
}

compile_parsed_survey <- function(parsed, id = slugify(basename(parsed$path))) {
  variables <- lapply(parsed$questions, function(question) {
    survey_variable(question$id, question$type, question$prompt, choices = question$choices)
  })
  states <- list(survey_state("start", transitions = list(
    survey_transition(if (length(parsed$questions)) parsed$questions[[1L]]$id else "end")
  )))
  if (length(parsed$questions)) {
    for (index in seq_along(parsed$questions)) {
      question <- parsed$questions[[index]]
      next_question <- if (index < length(parsed$questions)) parsed$questions[[index + 1L]] else NULL
      target <- if (is.null(next_question)) "end" else next_question$id
      transitions <- list(survey_transition(target))
      if (!is.null(next_question) && identical(next_question$depends_on, question$id)) {
        after_follow_up <- if (index + 1L < length(parsed$questions)) {
          parsed$questions[[index + 2L]]$id
        } else {
          "end"
        }
        transitions <- list(
          survey_transition(target, sprintf("%s == TRUE", question$id)),
          survey_transition(after_follow_up)
        )
      }
      states[[length(states) + 1L]] <- survey_state(question$id, question = question$id,
        transitions = transitions)
    }
  }
  states[[length(states) + 1L]] <- survey_state("end", terminal = TRUE)
  survey(id, variables, states, "start")
}

parsed_question_table <- function(parsed) {
  data.frame(
    id = vapply(parsed$questions, `[[`, character(1), "id"),
    original_id = vapply(parsed$questions, function(question) {
      if (is.null(question$original_id)) as.character(question$id) else as.character(question$original_id)
    }, character(1)),
    type = vapply(parsed$questions, `[[`, character(1), "type"),
    section = vapply(parsed$questions, function(question) {
      if (is.null(question$section)) "" else as.character(question$section)
    }, character(1)),
    prompt = vapply(parsed$questions, `[[`, character(1), "prompt"),
    source_line = vapply(parsed$questions, function(question) {
      if (!is.null(question$source_line)) as.integer(question$source_line) else as.integer(question$source_index)
    }, integer(1)),
    depends_on = vapply(parsed$questions, function(question) {
      if (is.null(question$depends_on)) "" else question$depends_on
    }, character(1)),
    stringsAsFactors = FALSE
  )
}

write_parsed_survey <- function(parsed, output_dir = "structured", name = "survey") {
  dir.create(output_dir, recursive = TRUE, showWarnings = FALSE)
  saveRDS(parsed, file.path(output_dir, paste0(name, ".rds")))
  write.table(parsed_question_table(parsed), file.path(output_dir, paste0(name, "_questions.tsv")),
    sep = "\t", row.names = FALSE, quote = TRUE, fileEncoding = "UTF-8")
  invisible(parsed)
}

mermaid_state_machine <- function(definition) {
  lines <- c("flowchart TD")
  variables <- setNames(definition$variables, vapply(definition$variables, `[[`, character(1), "id"))
  for (state in definition$states) {
    label <- if (isTRUE(state$terminal)) {
      "END"
    } else if (!is.null(state$question) && state$question %in% names(variables)) {
      variables[[state$question]]$prompt
    } else {
      state$id
    }
    label <- gsub("[[:cntrl:]]+", " ", label)
    label <- gsub("\"", "'", label, fixed = TRUE)
    shape <- if (isTRUE(state$terminal)) sprintf("%s((%s))", state$id, label) else sprintf("%s[\"%s\"]", state$id, label)
    lines <- c(lines, paste0("  ", shape))
  }
  for (state in definition$states) {
    for (transition in state$transitions) {
      transition_label <- transition$label
      if (is.null(transition_label) || !length(transition_label)) {
        transition_label <- if (identical(transition$when, "TRUE")) "" else transition$when
      }
        label <- if (!nzchar(transition_label)) "" else paste0("|", mermaid_edge_label(transition_label), "|")
      lines <- c(lines, sprintf("  %s -->%s %s", state$id, label, transition$target))
    }
  }
  paste(lines, collapse = "\n")
}

mermaid_edge_label <- function(label) {
  label <- gsub("[[:cntrl:]]+", " ", label)
  for (delimiter in c("|", "(", ")", "[", "]", "{", "}")) {
    label <- gsub(delimiter, " ", label, fixed = TRUE)
  }
  gsub("[[:space:]]+", " ", trimws(label))
}

dependency_edges <- function(definition) {
  variables <- vapply(definition$variables, `[[`, character(1), "id")
  variable_lookup <- setNames(variables, tolower(variables))
  rows <- list()
  for (state in definition$states) {
    for (transition in state$transitions) {
      if (identical(transition$when, "TRUE") || !transition$target %in% variables) next
      expression <- if (identical(transition$supported, FALSE)) transition$raw else transition$when
      tokens <- unique(regmatches(expression, gregexpr("[A-Za-z][A-Za-z0-9_]*", expression, perl = TRUE))[[1L]])
      sources <- unname(variable_lookup[tolower(tokens)])
      sources <- sources[!is.na(sources)]
      if (!length(sources)) next
      for (source in sources) {
        if (identical(source, transition$target)) next
        rows[[length(rows) + 1L]] <- data.frame(
          source = source,
          target = transition$target,
          predicate = transition$when,
          label = if (is.null(transition$label)) transition$when else transition$label,
          supported = !identical(transition$supported, FALSE),
          raw = if (is.null(transition$raw)) "" else transition$raw,
          stringsAsFactors = FALSE
        )
      }
    }
  }
  if (!length(rows)) {
    return(data.frame(source = character(), target = character(), predicate = character(),
      label = character(), supported = logical(), raw = character(), stringsAsFactors = FALSE))
  }
  edges <- do.call(rbind, rows)
  edges[!duplicated(edges[c("source", "target", "predicate")]), , drop = FALSE]
}

mermaid_variable_dependencies <- function(definition) {
  variables <- setNames(definition$variables, vapply(definition$variables, `[[`, character(1), "id"))
  ids <- names(variables)
  aliases <- setNames(sprintf("v%d", seq_along(ids)), ids)
  lines <- c("flowchart LR")
  for (id in ids) {
    prompt <- gsub("[[:cntrl:]]+", " ", variables[[id]]$prompt)
    prompt <- gsub("\"", "'", prompt, fixed = TRUE)
    lines <- c(lines, sprintf("  %s[\"%s: %s\"]", aliases[[id]], id, prompt))
  }
  edges <- dependency_edges(definition)
  for (index in seq_len(nrow(edges))) {
    edge <- edges[index, ]
    label <- mermaid_edge_label(edge$label)
    arrow <- if (isTRUE(edge$supported)) "-->" else "-.->"
    lines <- c(lines, sprintf("  %s %s|%s| %s", aliases[[edge$source]], arrow, label, aliases[[edge$target]]))
  }
  paste(lines, collapse = "\n")
}

write_state_machine <- function(definition, output_dir = "state_machine", name = definition$id) {
  dir.create(output_dir, recursive = TRUE, showWarnings = FALSE)
  audit <- audit_survey(definition)
  saveRDS(definition, file.path(output_dir, paste0(name, ".rds")))
  writeLines(mermaid_state_machine(definition), file.path(output_dir, paste0(name, ".mmd")), useBytes = TRUE)
  writeLines(mermaid_variable_dependencies(definition),
    file.path(output_dir, paste0(name, "_variable_dependencies.mmd")), useBytes = TRUE)
  write.table(dependency_edges(definition), file.path(output_dir, paste0(name, "_variable_dependencies.tsv")),
    sep = "\t", row.names = FALSE, quote = TRUE, fileEncoding = "UTF-8")
  route_rows <- do.call(rbind, lapply(definition$states, function(state) {
    if (!length(state$transitions)) return(NULL)
    data.frame(
      source = state$id,
      target = vapply(state$transitions, `[[`, character(1), "target"),
      predicate = vapply(state$transitions, `[[`, character(1), "when"),
      label = vapply(state$transitions, function(item) if (is.null(item$label)) "" else item$label, character(1)),
      supported = vapply(state$transitions, function(item) !identical(item$supported, FALSE), logical(1)),
      raw = vapply(state$transitions, function(item) if (is.null(item$raw)) "" else item$raw, character(1)),
      stringsAsFactors = FALSE
    )
  }))
  write.table(route_rows, file.path(output_dir, paste0(name, "_routes.tsv")),
    sep = "\t", row.names = FALSE, quote = TRUE, fileEncoding = "UTF-8")
  audit_lines <- c(
    paste0("survey: ", definition$id),
    paste0("ok: ", audit$ok),
    paste0("reachable_states: ", length(audit$reachable)),
    if (length(audit$errors)) c("errors:", paste0("- ", audit$errors)) else "errors: none",
    if (length(audit$warnings)) c("warnings:", paste0("- ", audit$warnings)) else "warnings: none"
  )
  writeLines(audit_lines, file.path(output_dir, paste0(name, "_audit.txt")), useBytes = TRUE)
  invisible(audit)
}

`%||%` <- function(left, right) if (is.null(left) || !length(left)) right else left