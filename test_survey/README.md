# Household Member Test Survey

This fixture is a deliberately small household survey for testing the DSL and diagramming ideas.

Each CSV row is one household member. `household_id` identifies the group, and `member_number` identifies a person within that group. The questionnaire definition supports up to six members so that the state machine remains readable while exercising conditional repeated blocks.

The fictional `HH001` household demonstrates:

- a married reference person and partner;
- a divorced grandparent living with the family;
- an adult, non-dependent child of one parent;
- a dependent child of the other parent;
- a younger child of both parents;
- children whose sibling relationships cannot be inferred from the relationship-to-reference field alone, but can be examined using `parent_person_numbers`.

## Run

From the project root:

```sh
Rscript --vanilla test_survey/household_survey.R
```

The script prints the state-machine audit and response issue matrix, then writes:

- `household_survey.mmd`: question-level flow diagram;
- `household_survey_variable_dependencies.mmd`: variable dependency diagram;
- `household_survey_routes.tsv`: route table;
- `household_structure.mmd`: conceptual household-to-member relationship diagram;
- `household_survey_dependency_pages/`: paginated dependency diagrams;
- `household_survey_variable_dependencies.pdf`: PDF dependency output.

The current DSL groups and indexes rows but does not yet enforce cross-row rules such as checking that every reported child is represented by a member row. This fixture is intended to become a test case for those future household-level constraints.

The generated audit may warn that the member roster start states do not have explicit `TRUE` fallbacks. Their two predicates are deliberately complementary (`household_size >= n` versus `household_size < n`), so the runtime behavior is deterministic; the warning demonstrates a current limitation of the generic audit rule.
