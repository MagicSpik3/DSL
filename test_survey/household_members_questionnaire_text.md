# Household Member Survey: Human-readable wording

This document gives a plain-language description of the small household fixture in `household_members.csv`. It is intended to mirror the tone and sequencing of the main WAS questionnaire, but in a simplified form for testing survey logic rather than production fieldwork.

## Household roster introduction

"We are interested in the people who usually live in this household. I would like to ask a few questions about each person who lives here, including the person who is the main contact for this household."

"Please think of everyone who normally lives here, including you, your partner, any adult children, older relatives, and any dependent children who live here most of the time."

## Household-level questions

### 1. Household size

"Including yourself, how many people usually live in this household?"

This is recorded as the `household_size` variable.

### 2. Household reference person

"Which person number is the household reference person? Please tell me which member is the main person in this household who provides information for this survey."

This is recorded as `reference_person_number`.

### 3. Household address

"What is the address or survey identifier for this household?"

This is recorded as `household_address` and is optional for the micro test fixture.

## Member-by-member questions

For each household member, the survey asks about that individual in turn.

### For each member

"I would now like to ask a few questions about each household member. Please think about the member identified by the person number shown on the screen."

1. "What is this person's name?"
   - captured as `member_n_name`

2. "How old is this person?"
   - captured as `member_n_age`

3. "How is this person related to the household reference person?"
   - examples: reference person, partner/spouse, parent, grandparent, child, sibling, other
   - captured as `member_n_relationship`

4. "What is this person's marital status?"
   - examples: single, married, civil partnership, separated, divorced, widowed
   - captured as `member_n_marital_status`

5. "If known, which person number or numbers are this person's parent or parents?"
   - captured as `member_n_parent_numbers`
   - this is deliberately optional to allow grandparents, step-parents, and partial information cases

6. "Is this person financially dependent on the household?"
   - captured as `member_n_dependent`

## Relationship notes for interviewers

This survey uses a household roster rather than a single combined response. The household is built from repeated member rows, each with a `member_number` and a relationship to the reference person.

The interviewer should:

- record every usual household resident;
- identify one person as the reference person;
- ask about relationship and dependency for each member;
- link children to their parent or parents where possible using `parent_person_numbers`;
- be careful that a grandparent or partner is not mistaken for a dependent child simply because they live in the same household.

## Example of the interview flow

"We will now list the people who usually live in this household. For each person, I will ask their age, how they are related to the reference person, whether they are married or in a civil partnership, and whether they depend on the household financially."

"For example, in a household with two adults and two children, the first two rows may be the adults, and later rows may be the children and any other relatives who live there."

## Why this wording matters

The main WAS survey is long and highly structured. It asks the respondent to identify household members, then asks follow-up questions about those members in a way that depends on the relationship and age structure of the household.

The test fixture is a simplified version of that idea. It uses a small household roster to test whether the DSL can represent:

- repeated person-level rows within a single household;
- reference-person logic;
- child and dependent relationships;
- age and relationship-based routing;
- roster consistency checks across member rows.

This short human text is enough to show the intended questionnaire behaviour without exposing actual personal information or replicating the full survey.
