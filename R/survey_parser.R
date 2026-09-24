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