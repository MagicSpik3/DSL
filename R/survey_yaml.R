# YAML questionnaire adapter.

yaml_character <- function(value) {
  if (is.null(value)) character() else as.character(unlist(value, use.names = FALSE))
}

yaml_question_type <- function(question) {
  choices <- question$pre_codes
  texts <- if (is.null(choices)) character() else vapply(choices, function(item) as.character(item$text), character(1))
  if (length(texts) == 2L && all(tolower(texts) %in% c("yes", "no"))) return("boolean")
  if (length(texts)) return("choice")
  response_type <- tolower(as.character(question$response_type %||% "unknown"))
  if (grepl("date", question$question, ignore.case = TRUE)) return("date")
  if (response_type %in% c("numeric", "number", "amount")) return("number")
  if (response_type %in% c("text", "open", "open-ended")) return("text")
  "unknown"
}

normalize_condition <- function(text) {
  value <- trimws(text)
  value <- sub("^(ask[[:space:]]+)?if[[:space:]]+", "", value, ignore.case = TRUE)
  value <- sub("[[:space:]]+[-;].*$", "", value)
  value <- sub("[[:space:]]+\\([^)]*\\)[[:space:]]*$", "", value)
  value <- gsub("[[:space:]]+AND[[:space:]]+", " && ", value, ignore.case = TRUE)
  value <- gsub("[[:space:]]+OR[[:space:]]+", " || ", value, ignore.case = TRUE)
  value <- gsub("<>", "!=", value, fixed = TRUE)
  value <- gsub("(?<![<>=!])=(?!=)", "==", value, perl = TRUE)
  value <- trimws(value)
  simple_match <- regexec("^([A-Za-z][A-Za-z0-9_]*)[[:space:]]*(==|!=|>=|<=|>|<)[[:space:]]*([-+]?[0-9]+(?:\\.[0-9]+)?|[A-Za-z][A-Za-z0-9_]*)$", value, perl = TRUE)
  simple_parts <- regmatches(value, simple_match)[[1L]]
  simple <- length(simple_parts) > 0L
  if (simple && !grepl("^[0-9.+-]+$", simple_parts[[4L]]) &&
      !toupper(simple_parts[[4L]]) %in% c("TRUE", "FALSE")) {
    rhs <- if (tolower(simple_parts[[4L]]) == "empty") "\"\"" else sprintf("\"%s\"", simple_parts[[4L]])
    value <- sprintf("%s %s %s", simple_parts[[2L]], simple_parts[[3L]], rhs)
  }
  list(predicate = value, supported = simple)
}

extract_yaml_conditions <- function(question) {
  text <- c(question$question, yaml_character(question$routing), yaml_character(question$interviewer_instructions))
  route_line <- "^[[:space:]]*(ask[[:space:]]+)?if[[:space:]]+[A-Za-z][A-Za-z0-9_]*"
  text <- text[grepl(route_line, text, ignore.case = TRUE)]
  if (!length(text)) return(list())
  conditions <- lapply(text, function(item) {
    match <- regexpr("\\bif\\b(.+)$", item, ignore.case = TRUE, perl = TRUE)
    raw <- if (match[[1L]] < 0L) item else substr(item, match[[1L]] + 2L, nchar(item))
    normalized <- normalize_condition(raw)
    c(normalized, list(raw = trimws(raw), source = item))
  })
  conditions <- Filter(function(item) grepl("[<>=]", item$predicate), conditions)
  if (!length(conditions)) return(list())
  keys <- vapply(conditions, function(item) item$predicate, character(1))
  conditions[!duplicated(keys)]
}

parse_yaml_survey <- function(path) {
  if (!requireNamespace("yaml", quietly = TRUE)) stop("The 'yaml' package is required to read questionnaire YAML.")
  document <- yaml::yaml.load_file(path)
  records <- document$questions
  if (!is.list(records)) stop("YAML survey must contain a top-level 'questions' list.")
  questions <- lapply(seq_along(records), function(index) {
    raw <- records[[index]]
    original_id <- as.character(raw$variable %||% paste0("question_", index))
    choices <- if (is.null(raw$pre_codes)) list() else lapply(raw$pre_codes, function(item) {
      list(code = item$code, text = as.character(item$text))
    })
    list(
      id = original_id,
      original_id = original_id,
      prompt = as.character(raw$question %||% ""),
      type = yaml_question_type(raw),
      choices = choices,
      route_conditions = extract_yaml_conditions(raw),
      routing = yaml_character(raw$routing),
      interviewer_instructions = yaml_character(raw$interviewer_instructions),
      text_fills = yaml_character(raw$text_fills),
      source_index = index,
      raw = raw
    )
  })
  ids <- vapply(questions, `[[`, character(1), "id")
  duplicate_ids <- duplicated(ids) | duplicated(ids, fromLast = TRUE)
  ids[duplicate_ids] <- make.unique(ids[duplicate_ids], sep = "__")
  for (index in seq_along(questions)) questions[[index]]$id <- ids[[index]]
  structure(list(path = path, questions = questions), class = "yaml_survey")
}

yaml_route_transition <- function(condition, target) {
  survey_transition(
    target = target,
    when = if (condition$supported) condition$predicate else "FALSE",
    label = condition$raw,
    supported = condition$supported,
    raw = condition$source
  )
}

compile_yaml_survey <- function(parsed, id = slugify(basename(parsed$path))) {
  variables <- lapply(parsed$questions, function(question) {
    choices <- lapply(question$choices, function(choice) choice$text)
    survey_variable(question$id, question$type, question$prompt, choices = choices)
  })
  states <- list(survey_state("start", transitions = list(
    survey_transition(if (length(parsed$questions)) parsed$questions[[1L]]$id else "end")
  )))
  for (index in seq_along(parsed$questions)) {
    question <- parsed$questions[[index]]
    transitions <- list()
    next_index <- index + 1L
    while (next_index <= length(parsed$questions) &&
           length(parsed$questions[[next_index]]$route_conditions)) {
      target_question <- parsed$questions[[next_index]]
      transitions <- c(transitions, lapply(target_question$route_conditions,
        yaml_route_transition, target = target_question$id))
      next_index <- next_index + 1L
    }
    fallback <- if (next_index <= length(parsed$questions)) parsed$questions[[next_index]]$id else "end"
    transitions[[length(transitions) + 1L]] <- survey_transition(
      fallback, label = if (length(transitions)) "otherwise" else NULL
    )
    states[[length(states) + 1L]] <- survey_state(question$id, question = question$id, transitions = transitions)
  }
  states[[length(states) + 1L]] <- survey_state("end", terminal = TRUE)
  survey(id, variables, states, "start")
}

write_yaml_survey_outputs <- function(path, structured_dir = "structured", state_machine_dir = "state_machine", id = NULL) {
  parsed <- parse_yaml_survey(path)
  survey_id <- id %||% slugify(tools::file_path_sans_ext(basename(path)))
  definition <- compile_yaml_survey(parsed, survey_id)
  write_parsed_survey(parsed, structured_dir, survey_id)
  audit <- write_state_machine(definition, state_machine_dir, survey_id)
  list(parsed = parsed, definition = definition, audit = audit)
}