source(file.path("R", "survey_dsl.R"))

definition <- readRDS(file.path("state_machine", "was_round9.rds"))
responses <- read.csv(file.path("unprocessed", "top_ten_pre_processing.csv"), stringsAsFactors = FALSE, check.names = FALSE, na.strings = c("", "NA"))
issues <- audit_survey_responses(definition, responses)

cat(sprintf("Checked %d row(s) against the WAS state machine.\n", nrow(responses)))
cat(sprintf("Found %d routing impossibility issue(s).\n", length(issues)))

if (length(issues)) {
  print(issues[seq_len(min(length(issues), 10L))])
}
