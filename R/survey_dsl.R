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