# Survey DSL Prototype

This project contains a small, dependency-free R framework for describing and checking survey logic.

## Project Layout

- `unprocessed/`: original free-text survey documents.
- `structured/`: first-pass parser output (`.rds` and question `.tsv`).
- `state_machine/`: compiled survey definition, audit report, and Mermaid diagram.
- `R/`: parser and state-machine implementation.

For poorly structured source material, `R/survey_parser.R` provides a deliberately conservative first stage. It identifies sections, question-shaped lines, answer options, guidance, source line numbers, and review cues before compiling the result into the DSL. It does not pretend that implicit routing or domain meaning can be recovered perfectly; those remain visible for human review.

The core model is deliberately narrow:

- `survey_variable()` defines captured data.
- `survey_state()` defines a question or control-flow node.
- `survey_transition()` defines a guarded transition between states.
- `survey_rule()` defines a cross-variable quality rule.
- `audit_survey()` checks the state graph before fieldwork.
- `run_survey()` traverses the graph using a respondent context.
- `check_response()` checks only questions reached by that respondent.

Try the example from the project root:

```sh
Rscript --vanilla examples/school_activity_survey.R
Rscript --vanilla tests/test_framework.R
Rscript --vanilla examples/parsed_survey_information.R
Rscript --vanilla examples/parsed_was_round9.R
```

The parsed survey example reads `unprocessed/Survey information.txt` and writes all generated artifacts to `structured/` and `state_machine/`.

The WAS example reads `unprocessed/WAS_Round9_Paper_Questionnaire.yaml` and writes:

- `structured/was_round9.rds` and `structured/was_round9_questions.tsv`
- `state_machine/was_round9.rds`, `state_machine/was_round9.mmd`, and `state_machine/was_round9_audit.txt`
- `state_machine/was_round9_routes.tsv`, containing every compiled edge, its normalized predicate, original route text, and whether the predicate is executable by the current evaluator.
- `state_machine/was_round9_variable_dependencies.mmd`, showing variables referenced by routing predicates and the questions they control.
- `state_machine/was_round9_variable_dependencies.tsv`, the tabular form of that dependency graph.
- `state_machine/was_round9_dependency_pages/`, paginated Mermaid dependency diagrams with explicit cross-page route markers and an `index.txt` manifest.
- `state_machine/was_round9_variable_dependencies.pdf`, a multipage vector PDF export of the dependency pages.

The paginated dependency diagrams use 75 variables per page by default. A cross-page relationship is represented on the source page as `route123 -> go to page_2` and on the destination page as `from page_1 - route123`. For manual layout work, call `write_dependency_suite()` with `page_count`, `mermaid_font_size`, `pdf_font_size`, `pdf_width`, and `pdf_height`.

For example, after loading the compiled definition:

```r
write_dependency_suite(
	definition,
	output_dir = "state_machine/manual_layout",
	name = "was_round9",
	page_count = 20,
	mermaid_font_size = 14,
	pdf_font_size = 0.65,
	pdf_width = 17,
	pdf_height = 11
)
```

`page_count` takes precedence over the default 75-variable page size and distributes variables as evenly as possible. The Mermaid font size is written into each page's Mermaid initialization directive; the PDF font size and page dimensions control the separate vector PDF export.

The YAML adapter uses stable `variable` codes as state IDs. Duplicate source codes receive deterministic suffixes such as `Ten1__2`, while `original_id` preserves the source value. Complex route expressions are retained in the edge report and Mermaid labels, marked unsupported in the audit, and skipped by runtime execution until a parser for that expression form is added.

Predicates are currently controlled R expressions such as `has_activities == TRUE` or `!has_activities && phone_time_daily_hours >= 4`. This is an intentionally small prototype boundary: a later parser can compile YAML, a visual editor, or legacy survey specifications into the same model without changing the execution and audit engine.