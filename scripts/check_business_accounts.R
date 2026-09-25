#!/usr/bin/env Rscript
# Simple checker for contradictory survey responses

args <- commandArgs(trailingOnly = TRUE)
infile <- ifelse(length(args) >= 1, args[1], "structured/business_accounts_v1_sample.csv")

df <- read.csv(infile, stringsAsFactors = FALSE, na.strings = c("", "NA"))

is_no <- function(x) {
  tolower(trimws(as.character(x))) %in% c("no", "n", "false", "0")
}

issues <- list()

# 1) If `able_to_report` == No, then most other numeric fields should be NA/empty
idx_unable_but_filled <- which(is_no(df$able_to_report) & (
  !is.na(df$total_turnover) & df$total_turnover != "" |
  !is.na(df$employment_costs) & df$employment_costs != "" |
  !is.na(df$materials_expenditure) & df$materials_expenditure != ""))
if (length(idx_unable_but_filled)) {
  issues$unable_but_filled <- idx_unable_but_filled
}

# 2) If `produces_env_goods_services` == No, then `pct_env_turnover` should be empty/NA/0
idx_env_no_but_pct <- which(is_no(df$produces_env_goods_services) & (
  !is.na(df$pct_env_turnover) & trimws(as.character(df$pct_env_turnover)) != "" & as.numeric(ifelse(df$pct_env_turnover=="", NA, df$pct_env_turnover)) > 0
))
if (length(idx_env_no_but_pct)) {
  issues$env_no_but_pct <- idx_env_no_but_pct
}

# 3) If `produces_env_goods_services` == Yes but pct missing -> maybe warning
idx_env_yes_but_missing_pct <- which(!is_no(df$produces_env_goods_services) & (
  is.na(df$pct_env_turnover) | trimws(as.character(df$pct_env_turnover))==""
))
if (length(idx_env_yes_but_missing_pct)) {
  issues$env_yes_but_missing_pct <- idx_env_yes_but_missing_pct
}

# Print a simple report
cat("Checked:", infile, "\n")
if (length(issues) == 0) {
  cat("No contradictions found.\n")
} else {
  cat("Contradictions / warnings found:\n")
  for (nm in names(issues)) {
    cat(sprintf(" - %s: rows %s\n", nm, paste(issues[[nm]], collapse = ", ") ))
  }
  # write flagged rows for inspection
  flagged_idx <- unique(unlist(issues))
  flagged <- df[flagged_idx, , drop = FALSE]
  out_file <- sub("\\.csv$", "_flagged.csv", infile)
  write.csv(flagged, out_file, row.names = FALSE, na = "")
  cat("Flagged rows written to:", out_file, "\n")
}
