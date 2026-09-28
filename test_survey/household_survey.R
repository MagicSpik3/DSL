source(file.path("R", "survey_dsl.R"))
source(file.path("R", "survey_parser.R"))

max_members <- 6L

member_fields <- function(member_number) {
  prefix <- paste0("member_", member_number)
  list(
    survey_variable(paste0(prefix, "_name"), "text",
      sprintf("Member %d: what is this person's name?", member_number)),
    survey_variable(paste0(prefix, "_age"), "number",
      sprintf("Member %d: what is this person's age?", member_number)),
    survey_variable(paste0(prefix, "_relationship"), "choice",
      sprintf("Member %d: how is this person related to the reference person?", member_number),
      choices = c("reference person", "partner/spouse", "parent", "grandparent", "child", "sibling", "other")),
    survey_variable(paste0(prefix, "_marital_status"), "choice",
      sprintf("Member %d: what is this person's marital status?", member_number),
      choices = c("single", "married", "civil partnership", "separated", "divorced", "widowed")),
    survey_variable(paste0(prefix, "_parent_numbers"), "text",
      sprintf("Member %d: enter the person number(s) of this person's parent(s), if known.", member_number),
      required = FALSE),
    survey_variable(paste0(prefix, "_dependent"), "boolean",
      sprintf("Member %d: is this person financially dependent on the household?", member_number))
  )
}

member_states <- function(member_number, next_state) {
  prefix <- paste0("member_", member_number)
  fields <- c("name", "age", "relationship", "marital_status", "parent_numbers", "dependent")
  states <- lapply(seq_along(fields), function(index) {
    field <- fields[[index]]
    target <- if (index < length(fields)) {
      paste0(prefix, "_", fields[[index + 1L]])
    } else {
      next_state
    }
    survey_state(
      paste0(prefix, "_", field),
      question = paste0(prefix, "_", field),
      transitions = list(survey_transition(target))
    )
  })
  states
}

member_start <- function(member_number, next_state) {
  prefix <- paste0("member_", member_number)
  survey_state(
    paste0(prefix, "_start"),
    transitions = list(
      survey_transition(paste0(prefix, "_name"),
        when = sprintf("household_size >= %d", member_number)),
      survey_transition(next_state,
        when = sprintf("household_size < %d", member_number))
    )
  )
}

member_variables <- unlist(lapply(seq_len(max_members), member_fields), recursive = FALSE)
member_starts <- lapply(seq_len(max_members), function(member_number) {
  next_state <- if (member_number < max_members) {
    paste0("member_", member_number + 1L, "_start")
  } else {
    "end"
  }
  member_start(member_number, next_state)
})
member_question_states <- unlist(lapply(seq_len(max_members), function(member_number) {
  next_state <- if (member_number < max_members) {
    paste0("member_", member_number + 1L, "_start")
  } else {
    "end"
  }
  member_states(member_number, next_state)
}), recursive = FALSE)

household_survey <- survey(
  id = "household_members_v1",
  variables = c(
    list(
      survey_variable("household_size", "number", "How many people live in this household?"),
      survey_variable("reference_person_number", "number", "Which person number is the household reference person?"),
      survey_variable("household_address", "text", "What is the household address or survey identifier?", required = FALSE)
    ),
    member_variables
  ),
  states = c(
    list(
      survey_state("start", transitions = list(survey_transition("household_size"))),
      survey_state("household_size", question = "household_size", transitions = list(
        survey_transition("reference_person_number", "household_size >= 1 && household_size <= 6"),
        survey_transition("end")
      )),
      survey_state("reference_person_number", question = "reference_person_number", transitions = list(
        survey_transition("household_address")
      )),
      survey_state("household_address", question = "household_address", transitions = list(
        survey_transition("member_1_start")
      ))
    ),
    member_starts,
    member_question_states,
    list(survey_state("end", terminal = TRUE))
  ),
  start = "start",
  rules = list(
    survey_rule(
      "invalid_household_size",
      "household_size < 1 || household_size > 6",
      "Household size must be between 1 and 6 for this test survey.",
      severity = "error"
    ),
    survey_rule(
      "invalid_reference_person",
      "reference_person_number < 1 || reference_person_number > household_size",
      "The reference person must be a member of the household.",
      severity = "error"
    )
  )
)

responses <- read.csv("test_survey/household_members.csv", stringsAsFactors = FALSE,
  check.names = FALSE, na.strings = c("", "NA"))

print(audit_survey(household_survey))
print(data.frame(
  household_key = survey_household_key(responses),
  members = ave(responses$member_number, survey_household_key(responses), FUN = length),
  stringsAsFactors = FALSE
))

write_state_machine(household_survey, output_dir = "test_survey", name = "household_survey")

structure_diagram <- c(
  "erDiagram",
  "  HOUSEHOLD ||--|{ MEMBER : contains",
  "  MEMBER ||--o{ MEMBER : parent_of",
  "  HOUSEHOLD {",
  "    string household_id PK",
  "    integer household_size",
  "    integer reference_person_number",
  "  }",
  "  MEMBER {",
  "    string household_id FK",
  "    integer member_number PK",
  "    string name",
  "    integer age",
  "    string relationship_to_reference",
  "    string marital_status",
  "    string parent_numbers",
  "    boolean dependent",
  "  }"
)
writeLines(structure_diagram, "test_survey/household_structure.mmd", useBytes = TRUE)
cat("Household survey artifacts written to test_survey/\n")
