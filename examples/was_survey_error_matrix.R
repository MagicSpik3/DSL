source(file.path("R", "survey_dsl.R"))

path <- file.path("unprocessed", "top_ten_pre_processing.csv")
definition <- readRDS(file.path("state_machine", "was_round9.rds"))
responses <- read.csv(path, stringsAsFactors = FALSE, check.names = FALSE, na.strings = c("", "NA"))
report <- survey_issue_report(definition, responses, output_path = file.path("was_round9_issue_matrix.csv"))

cat(sprintf("Rows examined: %d\n", report$summary$rows_examined))
cat(sprintf("Rows with issues: %d\n", report$summary$rows_with_issues))
cat(sprintf("Total issue flags: %d\n", report$summary$total_issues))

if (nrow(report$flagged_rows)) {
  print(report$flagged_rows[seq_len(min(nrow(report$flagged_rows), 10L)), , drop = FALSE])
}
