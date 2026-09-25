# A small, dependency-free survey DSL prototype.

survey_variable <- function(id, type, prompt, required = TRUE, choices = NULL) {
  stopifnot(is.character(id), length(id) == 1L, nzchar(id))
  stopifnot(is.character(type), length(type) == 1L)
  list(id = id, type = type, prompt = prompt, required = required, choices = choices)
}

survey_state <- function(id, question = NULL, transitions = list(), terminal = FALSE) {
  stopifnot(is.character(id), length(id) == 1L, nzchar(id))
  list(id = id, question = question, transitions = transitions, terminal = terminal)
}

survey_transition <- function(target, when = "TRUE", label = NULL, supported = TRUE, raw = NULL) {
  stopifnot(is.character(target), length(target) == 1L, nzchar(target))
  stopifnot(is.character(when), length(when) == 1L, nzchar(when))
  list(target = target, when = when, label = label, supported = supported, raw = raw)
}

survey_rule <- function(id, when, message, severity = "error") {
  list(id = id, when = when, message = message, severity = severity)
}

survey <- function(id, variables, states, start, rules = list()) {
  structure(
    list(id = id, variables = variables, states = states, start = start, rules = rules),
    class = "survey_definition"
  )
}

state_map <- function(definition) {
  setNames(definition$states, vapply(definition$states, `[[`, character(1), "id"))
}

evaluate_predicate <- function(predicate, context = list()) {
  if (!is.character(predicate) || length(predicate) != 1L) {
    stop("A predicate must be one character string.")
  }
  environment <- list2env(context, parent = baseenv())
  value <- tryCatch(
    eval(parse(text = predicate, keep.source = FALSE), envir = environment),
    error = function(error) stop(sprintf("Invalid predicate '%s': %s", predicate, error$message))
  )
  if (length(value) != 1L || is.na(value) || !is.logical(value)) {
    stop(sprintf("Predicate '%s' did not return one TRUE/FALSE value.", predicate))
  }
  value
}

choose_transition <- function(state, context) {
  for (candidate in state$transitions) {
    if (identical(candidate$supported, FALSE)) next
    if (isTRUE(evaluate_predicate(candidate$when, context))) return(candidate)
  }
  NULL
}

audit_survey <- function(definition) {
  states <- state_map(definition)
  state_ids <- vapply(definition$states, `[[`, character(1), "id")
  variable_ids <- vapply(definition$variables, `[[`, character(1), "id")
  targets <- unlist(lapply(definition$states, function(state) {
    vapply(state$transitions, `[[`, character(1), "target")
  }), use.names = FALSE)
  errors <- character()
  warnings <- character()

  if (anyDuplicated(state_ids)) errors <- c(errors, "State IDs must be unique.")
  if (anyDuplicated(variable_ids)) errors <- c(errors, "Variable IDs must be unique.")
  if (!definition$start %in% state_ids) errors <- c(errors, "Start state does not exist.")
  missing_targets <- setdiff(targets, state_ids)
  if (length(missing_targets)) {
    errors <- c(errors, paste("Unknown transition target(s):", paste(missing_targets, collapse = ", ")))
  }
  for (state in definition$states) {
    unsupported <- vapply(state$transitions, function(item) identical(item$supported, FALSE), logical(1))
    if (any(unsupported)) {
      warnings <- c(warnings, sprintf("State '%s' has %d unresolved route condition(s).", state$id, sum(unsupported)))
    }
    if (!state$terminal && !length(state$transitions)) {
      errors <- c(errors, sprintf("Non-terminal state '%s' has no transitions.", state$id))
    }
    if (!state$terminal && length(state$transitions) &&
        !any(vapply(state$transitions, function(item) identical(item$when, "TRUE"), logical(1)))) {
      warnings <- c(warnings, sprintf("State '%s' has no explicit TRUE fallback transition.", state$id))
    }
  }

  reachable <- character()
  frontier <- definition$start
  while (length(frontier)) {
    current <- frontier[[1L]]
    frontier <- frontier[-1L]
    if (current %in% reachable || !current %in% names(states)) next
    reachable <- c(reachable, current)
    frontier <- c(frontier, vapply(states[[current]]$transitions, `[[`, character(1), "target"))
  }
  unreachable <- setdiff(state_ids, reachable)
  if (length(unreachable)) {
    warnings <- c(warnings, paste("Unreachable state(s):", paste(unreachable, collapse = ", ")))
  }
  list(ok = !length(errors), errors = errors, warnings = warnings, reachable = reachable)
}

run_survey <- function(definition, answers = list(), max_steps = 100L) {
  states <- state_map(definition)
  context <- answers
  current <- definition$start
  path <- character()

  for (step in seq_len(max_steps)) {
    if (!current %in% names(states)) stop(sprintf("State '%s' does not exist.", current))
    state <- states[[current]]
    path <- c(path, current)
    if (isTRUE(state$terminal)) {
      return(list(status = "complete", state = current, context = context, path = path))
    }
    if (!is.null(state$question) && !state$question %in% names(context)) {
      return(list(status = "awaiting_input", state = current, question = state$question,
                  context = context, path = path))
    }
    transition <- choose_transition(state, context)
    if (is.null(transition)) {
      return(list(status = "blocked", state = current, context = context, path = path))
    }
    current <- transition$target
  }
  stop("Maximum survey steps exceeded; possible infinite loop.")
}

check_response <- function(definition, answers) {
  issues <- list()
  variables <- setNames(definition$variables, vapply(definition$variables, `[[`, character(1), "id"))
  execution <- run_survey(definition, answers)
  asked <- unique(vapply(state_map(definition)[execution$path], function(state) {
    if (is.null(state$question)) "" else state$question
  }, character(1)))
  for (id in intersect(names(variables), asked)) {
    variable <- variables[[id]]
    if (isTRUE(variable$required) && !id %in% names(answers)) {
      issues[[length(issues) + 1L]] <- list(id = id, severity = "error", message = "Required answer is missing.")
    }
  }
  for (rule in definition$rules) {
    if (isTRUE(evaluate_predicate(rule$when, answers))) {
      issues[[length(issues) + 1L]] <- list(id = rule$id, severity = rule$severity, message = rule$message)
    }
  }
  issues
}

survey_issue <- function(row, type, severity, message, variable = NULL, state = NULL) {
  list(
    row = row,
    type = type,
    severity = severity,
    variable = variable,
    state = state,
    message = message
  )
}

normalize_name <- function(value) {
  if (is.null(value)) return("")
  if (is.factor(value)) value <- as.character(value)
  gsub("[^A-Za-z0-9_]", "", toupper(as.character(value)))
}

survey_household_key <- function(responses, household_columns = c("OSGRIDREF", "AREA", "ADDRESS")) {
  if (!is.data.frame(responses)) {
    if (is.list(responses) && !is.data.frame(responses)) {
      responses <- as.data.frame(responses, stringsAsFactors = FALSE)
    } else {
      stop("responses must be a data frame or a list of answers.")
    }
  }

  candidate_names <- names(responses)
  parts <- rep("", nrow(responses))
  found_any <- FALSE

  for (column_name in household_columns) {
    exact_name <- candidate_names[tolower(candidate_names) == tolower(column_name)]
    if (!length(exact_name)) next
    value <- responses[[exact_name[[1L]]]]
    if (is.factor(value)) value <- as.character(value)
    values <- as.character(value)
    values[is.na(values)] <- ""
    values <- trimws(values)
    if (!length(parts)) parts <- rep("", length(values))
    if (!found_any) {
      parts <- values
      found_any <- TRUE
    } else {
      parts <- paste(parts, values, sep = "|")
    }
  }

  if (!found_any) {
    return(paste0("row_", seq_len(nrow(responses))))
  }

  fixed_parts <- trimws(parts)
  fixed_parts[!nzchar(fixed_parts)] <- paste0("row_", which(!nzchar(fixed_parts)))
  fixed_parts
}

coerce_numeric_answer <- function(value) {
  if (is.null(value) || length(value) == 0L || is.na(value)) return(NA_real_)
  if (is.factor(value)) value <- as.character(value)
  text <- trimws(as.character(value))
  if (!nzchar(text) || toupper(text) == "NA") return(NA_real_)
  numeric_value <- suppressWarnings(as.numeric(text))
  if (length(numeric_value) != 1L || is.na(numeric_value) || !is.finite(numeric_value)) return(NA_real_)
  numeric_value
}

is_populated_answer <- function(value) {
  if (is.null(value) || length(value) == 0L || is.na(value)) return(FALSE)
  if (is.factor(value)) value <- as.character(value)
  if (is.character(value)) {
    return(length(trimws(value)) > 0L && !all(is.na(trimws(value))))
  }
  !is.na(value)
}

count_like_variables <- function(names) {
  normalized <- vapply(names, normalize_name, character(1))
  matches <- grepl("NCHILD|NUMCHILD|NDEPC|NUMDEP|CHILDREN|DEPENDENTS|KIDS|DEPCH|NCH|NUMCH|NUMCIVPTR|NUMPSING|NUMMPART", normalized)
  names[matches]
}

survey_row_routing_issues <- function(definition, answers, row_number = NA_integer_) {
  issues <- list()
  for (state in definition$states) {
    if (isTRUE(state$terminal) || !length(state$transitions)) next
    active <- vapply(state$transitions, function(candidate) {
      if (identical(candidate$supported, FALSE)) return(FALSE)
      value <- tryCatch(evaluate_predicate(candidate$when, answers), error = function(error) FALSE)
      isTRUE(value)
    }, logical(1))
    if (sum(active) > 1L) {
      issues[[length(issues) + 1L]] <- survey_issue(
        row = row_number,
        type = "ambiguous_route",
        severity = "error",
        state = state$id,
        message = sprintf("State '%s' has %d active transitions under this respondent context: %s.",
          state$id, sum(active), paste(vapply(state$transitions[active], `[[`, character(1), "when"), collapse = ", "))
      )
    }
  }

  answer_names <- names(answers)
  count_columns <- count_like_variables(answer_names)
  for (count_name in count_columns) {
    count_value <- coerce_numeric_answer(answers[[count_name]])
    if (is.na(count_value) || count_value > 0) next
    if (!isTRUE(all.equal(count_value, 0))) next

    normalized_names <- vapply(answer_names, normalize_name, character(1))
    relevant_names <- answer_names[grepl("CHILD|DEP|KID", normalized_names)]
    relevant_names <- setdiff(relevant_names, count_name)
    filled_name_fields <- relevant_names[vapply(relevant_names, function(field) {
      is_populated_answer(answers[[field]])
    }, logical(1))]
    if (!length(filled_name_fields)) next
    issues[[length(issues) + 1L]] <- survey_issue(
      row = row_number,
      type = "count_name_mismatch",
      severity = "error",
      variable = count_name,
      message = sprintf(
        "count_name_mismatch: Variable '%s' is 0 but the row also contains populated child/dependent name fields (%s). This means the respondent reports no children/dependants while still naming them, which is inconsistent with the survey routing logic.",
        count_name,
        paste(filled_name_fields, collapse = ", ")
      )
    )
  }

  issues
}

audit_survey_responses <- function(definition, responses) {
  if (!is.data.frame(responses)) {
    if (is.list(responses) && !is.data.frame(responses)) {
      responses <- as.data.frame(responses, stringsAsFactors = FALSE)
    } else {
      stop("responses must be a data frame or a list of answers.")
    }
  }
  issues <- list()
  for (row_number in seq_len(nrow(responses))) {
    row_context <- as.list(responses[row_number, , drop = FALSE])
    row_issues <- survey_row_routing_issues(definition, row_context, row_number)
    if (length(row_issues)) {
      issues <- c(issues, row_issues)
    }
  }
  issues
}

audit_csv_against_survey <- function(definition, path) {
  responses <- read.csv(path, stringsAsFactors = FALSE, check.names = FALSE, na.strings = c("", "NA"))
  audit_survey_responses(definition, responses)
}

survey_response_issue_matrix <- function(definition, responses, output_path = NULL) {
  if (!is.data.frame(responses)) {
    if (is.list(responses) && !is.data.frame(responses)) {
      responses <- as.data.frame(responses, stringsAsFactors = FALSE)
    } else {
      stop("responses must be a data frame or a list of answers.")
    }
  }

  issues <- audit_survey_responses(definition, responses)
  household_key <- survey_household_key(responses)
  household_member_index <- ave(household_key, household_key, FUN = function(x) seq_along(x))

  if (!length(issues)) {
    report <- data.frame(
      row_id = seq_len(nrow(responses)),
      household_key = household_key,
      household_member_index = as.integer(household_member_index),
      issue_count = 0L,
      issue_types = "",
      has_error = FALSE,
      stringsAsFactors = FALSE
    )
    if (!is.null(output_path)) write.csv(report, output_path, row.names = FALSE)
    return(report)
  }

  issue_variables <- unique(vapply(issues, function(issue) {
    if (is.null(issue$variable) || !nzchar(as.character(issue$variable))) "" else as.character(issue$variable)
  }, character(1)))
  issue_variables <- sort(issue_variables[nzchar(issue_variables)])

  report <- data.frame(
    row_id = seq_len(nrow(responses)),
    household_key = household_key,
    household_member_index = as.integer(household_member_index),
    issue_count = 0L,
    issue_types = "",
    has_error = FALSE,
    stringsAsFactors = FALSE
  )
  for (column_name in issue_variables) {
    report[[column_name]] <- ""
  }

  for (issue in issues) {
    row_id <- as.integer(issue$row)
    if (is.na(row_id) || row_id < 1L || row_id > nrow(responses)) next
    report$issue_count[row_id] <- report$issue_count[row_id] + 1L
    issue_types <- report$issue_types[row_id]
    next_type <- if (is.null(issue$type)) "unknown" else as.character(issue$type)
    report$issue_types[row_id] <- if (!nzchar(issue_types)) next_type else paste(issue_types, next_type, sep = "; ")
    report$has_error[row_id] <- TRUE
    if (!is.null(issue$variable) && nzchar(as.character(issue$variable))) {
      variable_name <- as.character(issue$variable)
      match_name <- names(report)[vapply(names(report), function(name) {
        normalize_name(name) == normalize_name(variable_name)
      }, logical(1))]
      if (length(match_name)) {
        variable_name <- match_name[[1L]]
      }
      current <- report[[variable_name]][row_id]
      new_value <- if (!nzchar(current)) next_type else paste(current, next_type, sep = "; ")
      report[[variable_name]][row_id] <- new_value
    }
  }

  if (!is.null(output_path)) write.csv(report, output_path, row.names = FALSE)
  report
}

survey_issue_report <- function(definition, responses, output_path = NULL) {
  report <- survey_response_issue_matrix(definition, responses, output_path = output_path)
  flagged <- report[report$has_error, , drop = FALSE]
  list(
    summary = data.frame(
      rows_examined = nrow(responses),
      rows_with_issues = nrow(flagged),
      total_issues = sum(report$issue_count),
      stringsAsFactors = FALSE
    ),
    matrix = report,
    flagged_rows = flagged
  )
}