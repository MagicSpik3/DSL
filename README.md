# Survey DSL Prototype

This project contains a small R framework for describing and checking survey logic. The YAML questionnaire adapter requires the `yaml` package.

## Project Layout

- `unprocessed/`: original free-text survey documents.
- `structured/`: first-pass parser output (`.rds` and question `.tsv`).
- `state_machine/`: compiled survey definition, audit report, and Mermaid diagram.
- `R/`: parser and state-machine implementation.

## Available Tools

The R source files provide the following tools:

- **Define a survey:** `survey_variable()`, `survey_state()`, `survey_transition()`, `survey_rule()`, and `survey()` build variables, question/control-flow states, guarded routes, and response rules.
- **Inspect and run survey logic:** `audit_survey()` checks state IDs, transition targets, reachability, fallbacks, and unresolved routes. `run_survey()` follows supported routes for an answer context. `check_response()` checks required answers on the path taken and evaluates response rules.
- **Import survey specifications:** `parse_survey_text()` conservatively extracts questions, sections, choices, and review cues from plain text. `parse_yaml_survey()` reads questionnaire YAML using the `yaml` package. `compile_parsed_survey()` and `compile_yaml_survey()` turn parsed specifications into the common survey model.
- **Check response data:** `audit_survey_responses()` checks each data-frame row for ambiguous routes and selected row-level count/name contradictions. `audit_csv_against_survey()` reads a CSV for the same checks. `survey_issue_report()` returns a summary, a row-level issue matrix, and flagged rows; `survey_response_issue_matrix()` can also write the matrix to CSV.
- **Group household rows:** `survey_household_key()` combines available `OSGRIDREF`, `AREA`, and `ADDRESS` columns into a household key. The issue matrix adds that key and a within-household member index to each response row.
- **Visualize and export:** `mermaid_state_machine()` and `mermaid_variable_dependencies()` create Mermaid diagrams. `write_state_machine()` and `write_dependency_suite()` write compiled artifacts, audit reports, dependency diagrams, and PDF output.

These functions currently live in `R/` and are sourced directly by the examples and tests; the package `NAMESPACE` does not currently declare exported functions. Relevant examples and scripts include `examples/school_activity_survey.R`, `examples/parsed_survey_information.R`, `examples/parsed_was_round9.R`, `examples/check_was_routing_impossibilities.R`, `examples/was_survey_error_matrix.R`, and `scripts/check_business_accounts.R`.

## A tiny tutorial: Boolean algebra for surveys

The core DSL idea is simple: a survey question is a variable, a state is a place in the interview, and a transition is a guarded proposition. In other words, we are building Boolean logic for human responses rather than for numbers alone.

The smallest possible atomic example is a three-way answer set:

```r
# A = yes
# B = no
# D = did not answer
#
# Excluding the "did not answer" case makes the answer space incomplete.
# A, B, and D should be treated as mutually exclusive states.
```

A minimal R definition looks like this:

```r
survey_variable("willing_to_answer", "choice",
  "Are you willing to answer a basic survey?",
  choices = c("yes", "no", "did_not_answer"))

survey_state("ask_willing", question = "willing_to_answer", transitions = list(
  survey_transition("next_question", "willing_to_answer == 'yes'"),
  survey_transition("end", "willing_to_answer == 'no'"),
  survey_transition("end", "is.na(willing_to_answer) || willing_to_answer == 'did_not_answer'")
))
```

This reads as a survey rule system:

- `willing_to_answer == 'yes'` means the proposition A is true.
- `willing_to_answer == 'no'` means the proposition B is true.
- `is.na(willing_to_answer) || willing_to_answer == 'did_not_answer'` means the proposition D is true.
- A and B and D are mutually exclusive; together they cover the valid response space for the question.

That is the survey analogue of Boolean algebra:

- a variable can be set to a state;
- a guard is a proposition;
- a transition is implication; and
- a rule is a constraint that must remain true for the respondent context.

The smallest atomic rules are therefore:

1. `TRUE` guard: continue by default.
2. `A` guard: route to the yes branch.
3. `B` guard: route to the no branch.
4. `D` guard: route to the missing or follow-up branch.
5. cross-variable rule: if `A` then require a follow-up answer, but if `B` or `D` then skip it.

This is the first layer of the DSL: not a complicated system, but a disciplined way to model logic as state transitions plus validation rules.

## Routing excluded questions

The next atomic idea is exclusion by routing. When two answer categories are mutually exclusive, the survey should ask only the matching follow-up question and never the opposite one.

Take a fertility example:

- What gender are you? (M / F)
- If F: Have you given birth?
- If M: Have you fathered a child?

This is not "two independent yes/no questions". It is one categorical variable with a partitioned outcome space:

```r
# Partition: gender ∈ {M, F}
# Exclusion: M and F cannot both be true.
# Follow-up: F -> asked about childbirth, M -> asked about fathering.

survey_variable("gender", "choice",
  "What gender are you?",
  choices = c("M", "F"))

survey_state("gender_question", question = "gender", transitions = list(
  survey_transition("given_birth_question", "gender == 'F'"),
  survey_transition("fathered_child_question", "gender == 'M'"),
  survey_transition("end", "is.na(gender) || gender == 'did_not_answer'")
))

survey_state("given_birth_question", question = "given_birth", transitions = list(
  survey_transition("end")
))

survey_state("fathered_child_question", question = "fathered_child", transitions = list(
  survey_transition("end")
))
```

The rule is conceptual and very small:

- `gender == 'F'` implies the `given_birth` question is relevant.
- `gender == 'M'` implies the `fathered_child` question is relevant.
- `gender == 'F'` excludes `fathered_child`.
- `gender == 'M'` excludes `given_birth`.
- `M` and `F` are mutually exclusive by design, so the survey never asks both follow-up questions for the same respondent.

This is the survey analogue of exclusive-or logic: the follow-up path is selected by the category that is true, and the other branch is logically excluded. In DSL terms, a routed question is a state whose relevance is defined by a guard, and the guard is an atomic proposition about the answer space.

## Multi-Row Surveys and Household Consistency

For a multi-row survey, the household is the group and each person is a separate member record (row). A household with four people therefore has four person rows with the same household key, not one row per household. Household-level answers may be repeated on those rows or stored in a related household record; either way, their meaning and consistency across the group must be explicit.

For example, if a household member reports that they have two children living in the household, the household data should contain two distinct member rows representing those children. A research or validation workflow should compare the reported count with the number of matching child-member records in that same household, using the survey's definition of a child and who is included in the count. More generally, linked answers across member rows should agree with household-level answers and with each other; a mismatch should be reported against the household and the relevant rows.

**Current limitation:** the existing response audit groups rows by household key and assigns member indexes, and it can flag some contradictions within an individual row. It does not yet compare a reported child/dependent count with the number of corresponding member rows, nor does it otherwise enforce general cross-row household consistency. Treat those checks as requirements for future research and implementation, not as existing functionality. The current route evaluator also skips route conditions marked unsupported during YAML compilation; their source text remains available in the audit and route outputs for review.

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



That balance right there is the exact boundary between computer science as a research discipline and software engineering as a craft. Building a production engine using standard graph tools today gives you immediate value, while laying out a clear, formal model keeps the door open for deep verification later.

To bridge the two, you can design your MVP using graph theory primitives that directly mirror how a formal proof assistant like Lean would model the problem.

---

### The MVP: Mapping Survey Logic to Graph Primitives

In graph theory, a survey flow is simply a **Directed Acyclic Graph (DAG)** with deterministic edge conditions. By framing your domain model strictly around graph primitives, you get instant access to existing, battle-tested algorithms (like NetworkX or `petgraph`) to enforce your three rules.

```
       [ Start ]
           |
       (Q1: Age)
        /     \
   [>= 18]   [< 18]
      /         \
  (Q2: Work)  (Q3: School)   [Q4: Disconnected] <-- Island Question!
      \         /
       [  End  ]

```

Here is how your three determinism requirements map directly to standard graph algorithms:

#### 1. No Island Questions $\rightarrow$ **Reachability (Weak Connectivity / Traversal)**

* **The Graph Condition:** Every node $V$ (except the entry node) must be reachable from $V_{\text{start}}$.
* **The MVP Implementation:** Run a **Breadth-First Search (BFS)** or **Depth-First Search (DFS)** starting at $V_{\text{start}}$. Any node left unvisited after traversal is an isolated island.

#### 2. No Circular Loops $\rightarrow$ **Acyclicity (Topological Sort / DFS)**

* **The Graph Condition:** The directed graph $G = (V, E)$ contains no back-edges (it must be a DAG).
* **The MVP Implementation:** Run **Kahn’s Algorithm** or **Tarjan’s Strongly Connected Components (SCC)** algorithm. If Kahn’s algorithm cannot consume all nodes, or if Tarjan finds an SCC with a size $> 1$, a circular loop exists.

#### 3. No Contradictions / Determinism $\rightarrow$ **Edge Guard Mutex & Exhaustiveness**

* **The Graph Condition:** For any node $V_i$ with outgoing edges $E = \{(V_i, V_j, g_1), (V_i, V_k, g_2), \dots\}$ where $g$ represents a predicate guard (e.g., `answer == "Yes"`):
1. **Mutually Exclusive:** $g_1 \land g_2 \equiv \text{False}$ (no overlapping conditions causing non-deterministic branching).
2. **Exhaustive:** $g_1 \lor g_2 \lor \dots \equiv \text{True}$ (no "dead ends" where a valid user answer yields no valid outgoing edge before reaching an End node).


* **The MVP Implementation:** Evaluate edge predicates against the allowable domain values of the question to verify that every possible answer routes to *exactly one* target node.

---

### The "Hello World" Formal Blueprint (Mental Model for Lean)

If you ever decide to take a slice of this logic and formally prove it in Lean, the code above translates almost 1:1 into formal types:

```lean
-- 1. Represent questions and transition rules as inductive types
inductive Node
| Question (id : Nat)
| End

structure Edge where
  fromNode : Node
  toNode   : Node
  guard    : String -- Simplified predicate

-- 2. Define what a valid path means recursively
inductive Reachable (edges : List Edge) : Node → Node → Prop
| direct (e : Edge) (h : e ∈ edges) : Reachable edges e.fromNode e.toNode
| step (e : Edge) (h : e ∈ edges) (r : Reachable edges e.toNode target) : 
    Reachable edges e.fromNode target

-- 3. Define the theorem: "No Island Questions"
def NoIslands (startNode : Node) (allNodes : List Node) (edges : List Edge) : Prop :=
  ∀ n ∈ allNodes, n = startNode ∨ Reachable edges startNode n

```

In Lean, you don't just run a loop to *check* if `NoIslands` holds; you construct a proof that proves `NoIslands` **must** hold for every generated graph.

---

### Recommended Evolutionary Path

1. **Phase 1 (The MVP):** Build a domain model in your language of choice where a survey is represented purely as an adjacency list of nodes and guarded edges. Use a standard graph library to run BFS (islands) and Kahn's algorithm (cycles) on save/publish.
2. **Phase 2 (Property-Based Testing):** Use a tool like **Hypothesis** (Python) or **fast-check** (TypeScript) to randomly generate thousands of survey graphs, testing that your validator reliably catches edge cases and synthetic loops.
3. **Phase 3 (Formal Methods / Lean Exploration):** Extract the core graph representation into Lean 4 to prove that your graph-validation algorithm is *sound* (it never marks an invalid survey as valid) and *complete* (it never marks a valid survey as invalid).

What language or framework are you planning to use for building this initial MVP?