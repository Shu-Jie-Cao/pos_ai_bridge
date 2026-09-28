#!/bin/bash
set -euo pipefail

# ============================================================
# PoS PAPER <-> RESEARCH AGENT BRIDGE
# ============================================================
#
# AI 1:
#   /Users/shu-jie/research proj/pos_overleaf
#
# AI 2:
#   /Users/shu-jie/research proj/pos_research
#
# Bridge:
#   /Users/shu-jie/research proj/pos_ai_bridge
#
# This script:
#
#   Technical problem
#        ↓
#   AI 1 extracts manuscript context
#        ↓
#   AI 2 investigates / proves / attacks
#        ↓
#   Human approval
#        ↓
#   AI 1 integrates validated result
#        ↓
#   LaTeX compile
#        ↓
#   Human review
#
# It NEVER commits or pushes to Overleaf automatically.
# ============================================================


# ============================================================
# CONFIG
# ============================================================

PAPER_REPO="/Users/shu-jie/research proj/pos_overleaf"
RESEARCH_REPO="/Users/shu-jie/research proj/pos_research"
BRIDGE_DIR="/Users/shu-jie/research proj/pos_ai_bridge"
RUNS_DIR="$BRIDGE_DIR/runs"

EXPECTED_PAPER_BRANCH="ai-paper-editor"

mkdir -p "$RUNS_DIR"


# ============================================================
# HELPER FUNCTIONS
# ============================================================

separator() {
    echo
    echo "============================================================"
    echo "$1"
    echo "============================================================"
    echo
}

fail() {
    echo
    echo "ERROR: $1"
    echo
    exit 1
}


# ============================================================
# BASIC CHECKS
# ============================================================

separator "Checking environment"

command -v codex >/dev/null 2>&1 \
    || fail "Codex CLI is not installed or not in PATH."

command -v git >/dev/null 2>&1 \
    || fail "Git is not available."

command -v latexmk >/dev/null 2>&1 \
    || fail "latexmk is not available."

[ -d "$PAPER_REPO/.git" ] \
    || fail "Paper repository not found at: $PAPER_REPO"

[ -d "$RESEARCH_REPO" ] \
    || fail "Research repository not found at: $RESEARCH_REPO"

[ -f "$PAPER_REPO/AGENTS.md" ] \
    || fail "AI 1 AGENTS.md not found."

[ -f "$RESEARCH_REPO/AGENTS.md" ] \
    || fail "AI 2 AGENTS.md not found."

CURRENT_BRANCH="$(git -C "$PAPER_REPO" branch --show-current)"

if [ "$CURRENT_BRANCH" != "$EXPECTED_PAPER_BRANCH" ]; then
    fail "Paper repo is on branch '$CURRENT_BRANCH', expected '$EXPECTED_PAPER_BRANCH'."
fi

echo "Paper Agent repo:    $PAPER_REPO"
echo "Research Agent repo: $RESEARCH_REPO"
echo "Paper branch:        $CURRENT_BRANCH"
echo "Environment OK."


# ============================================================
# CHECK FOR PRE-EXISTING TRACKED PAPER CHANGES
# ============================================================

separator "Checking local paper state"

if ! git -C "$PAPER_REPO" diff --quiet; then
    echo "The paper repository already contains uncommitted tracked changes."
    echo
    echo "Please review them first:"
    echo
    echo "  cd \"$PAPER_REPO\""
    echo "  git diff"
    echo
    echo "Then commit, revert, or otherwise resolve them before"
    echo "starting an automated research handoff."
    exit 1
fi

if ! git -C "$PAPER_REPO" diff --cached --quiet; then
    echo "The paper repository contains staged but uncommitted changes."
    echo
    echo "Please resolve them before running this workflow."
    exit 1
fi

echo "No pre-existing tracked manuscript changes."


# ============================================================
# CHECK OVERLEAF BEFORE STARTING
# ============================================================

separator "Checking Overleaf for advisor changes"

git -C "$PAPER_REPO" fetch overleaf

REMOTE_AHEAD="$(
    git -C "$PAPER_REPO" rev-list \
        --right-only \
        --count \
        HEAD...overleaf/master
)"

if [ "$REMOTE_AHEAD" -ne 0 ]; then
    echo "STOP."
    echo
    echo "Overleaf contains $REMOTE_AHEAD commit(s) that are not"
    echo "present in your local paper repository."
    echo
    echo "Your advisor may have modified the manuscript."
    echo
    echo "Inspect with:"
    echo
    echo "  cd \"$PAPER_REPO\""
    echo "  git log --oneline HEAD..overleaf/master"
    echo "  git diff HEAD..overleaf/master"
    echo
    echo "Integrate the Overleaf changes before running this script."
    exit 1
fi

echo "No new Git-visible Overleaf manuscript changes."

# ============================================================
# OPTIONAL MANUAL TRIAGE OVERRIDE
# ============================================================

TRIAGE_OVERRIDE=""

case "${1:-}" in
    --direct)
        TRIAGE_OVERRIDE="DIRECT_EDIT"
        shift
        ;;
    --quick)
        TRIAGE_OVERRIDE="QUICK_VERIFY"
        shift
        ;;
    --full)
        TRIAGE_OVERRIDE="FULL_RESEARCH"
        shift
        ;;
esac

# ============================================================
# GET THE TECHNICAL PROBLEM
# ============================================================

separator "Reading research problem"

if [ "$#" -gt 0 ]; then
    ISSUE="$*"
else
    if ! command -v pbpaste >/dev/null 2>&1; then
        fail "No argument supplied and pbpaste is unavailable."
    fi

    ISSUE="$(pbpaste)"
fi

if [ -z "${ISSUE//[[:space:]]/}" ]; then
    fail "Research problem is empty."
fi

TIMESTAMP="$(date +"%Y%m%d-%H%M%S")"
RUN_DIR="$RUNS_DIR/$TIMESTAMP"

mkdir -p "$RUN_DIR"

printf "%s\n" "$ISSUE" > "$RUN_DIR/problem.txt"

# ============================================================
# TRIAGE
# ============================================================

separator "TRIAGE — Classifying technical issue"

TRIAGE_PROMPT="$RUN_DIR/triage-prompt.txt"
TRIAGE_RESULT="$RUN_DIR/triage-result.md"

if [ -n "$TRIAGE_OVERRIDE" ]; then

    TRIAGE_MODE="$TRIAGE_OVERRIDE"

    {
        echo "TRIAGE: $TRIAGE_MODE"
        echo
        echo "RATIONALE: User manually selected this workflow."
    } > "$TRIAGE_RESULT"

else

    cat > "$TRIAGE_PROMPT" <<'EOF'
READ ONLY.

Do not modify any files.

You are acting only as a TRIAGE AGENT.

Your job is NOT to solve the technical issue.

Classify the issue into exactly one of these three categories:

DIRECT_EDIT
QUICK_VERIFY
FULL_RESEARCH


============================================================
DIRECT_EDIT
============================================================

Use DIRECT_EDIT only when the correct technical change is already
determined from local manuscript evidence and no genuine research
reasoning is needed.

Typical examples:

- a prose sign is inconsistent with the immediately following equation;
- prose says "increase" where the established definition clearly implies
  "decrease";
- an obvious index typo is contradicted by the surrounding equations;
- terminology is technically wrong but the intended replacement is
  unambiguous from an existing definition;
- a local sentence contradicts an already-established result.

The correction must be locally evident.

No new lemma, proof, assumption, model change, or nontrivial derivation
should be required.


============================================================
QUICK_VERIFY
============================================================

Use QUICK_VERIFY when the issue is localized but requires a short
technical verification before editing.

Typical examples:

- checking whether one transition equation follows from a definition;
- verifying a sign or index that is not immediately obvious;
- checking a short probability calculation;
- checking whether a local case distinction is exhaustive;
- verifying a short implication using already-established lemmas;
- checking a small boundary case.

The problem should be resolvable using a limited amount of mathematical
reasoning and existing manuscript assumptions.

It should NOT require a new theorem, new state representation, major
counterexample search, or substantial model development.


============================================================
FULL_RESEARCH
============================================================

Use FULL_RESEARCH when the issue involves genuine research uncertainty.

Typical examples:

- a possible proof gap;
- a missing lemma;
- a new assumption may be required;
- it is unclear whether a claim is true;
- a counterexample may exist;
- the Markov state may be insufficient;
- a protocol or model extension is being considered;
- a new state variable may be needed;
- a result may fail under relaxed assumptions;
- substantial multi-step derivation is required;
- several parts of the manuscript depend on the issue.


============================================================
IMPORTANT
============================================================

Prefer the cheapest category that is sufficient.

Do NOT classify a problem as FULL_RESEARCH merely because it is
mathematical.

Do NOT classify a problem as DIRECT_EDIT merely because the correction
looks plausible.

If a short verification is enough, choose QUICK_VERIFY.

Do not scan the entire manuscript unless needed for classification.


Your response must begin with EXACTLY one of:

TRIAGE: DIRECT_EDIT
TRIAGE: QUICK_VERIFY
TRIAGE: FULL_RESEARCH

Then provide:

RATIONALE:
A concise explanation of why this category is sufficient.

The technical issue follows:

------------------------------------------------------------
EOF

    cat "$RUN_DIR/problem.txt" >> "$TRIAGE_PROMPT"

    (
        cd "$PAPER_REPO"
        codex exec \
            -c 'model_reasoning_effort="low"' \
            - < "$TRIAGE_PROMPT"
    ) > "$TRIAGE_RESULT"

    TRIAGE_MODE="$(
        sed -n 's/^TRIAGE: //p' "$TRIAGE_RESULT" | head -n 1
    )"

fi

case "$TRIAGE_MODE" in
    DIRECT_EDIT|QUICK_VERIFY|FULL_RESEARCH)
        ;;
    *)
        fail "Triage Agent returned an invalid classification: $TRIAGE_MODE"
        ;;
esac

echo
cat "$TRIAGE_RESULT"
echo
echo "Selected workflow: $TRIAGE_MODE"

echo "Research problem:"
echo
cat "$RUN_DIR/problem.txt"
echo
echo "Run directory:"
echo "$RUN_DIR"

# ============================================================
# DIRECT EDIT PATH
# ============================================================

if [ "$TRIAGE_MODE" = "DIRECT_EDIT" ]; then

    separator "DIRECT EDIT — Local technical correction"

    echo "The issue was classified as a direct technical correction."
    echo
    cat "$TRIAGE_RESULT"
    echo

    read -r -p \
    "Allow AI 1 to make this confirmed local technical correction? [y/N] " \
    ANSWER

    case "$ANSWER" in
        y|Y|yes|YES)
            ;;
        *)
            echo "Stopped. No manuscript files were modified."
            exit 0
            ;;
    esac

    # Check Overleaf one more time before editing

    git -C "$PAPER_REPO" fetch overleaf

    REMOTE_AHEAD="$(
        git -C "$PAPER_REPO" rev-list \
            --right-only \
            --count \
            HEAD...overleaf/master
    )"

    if [ "$REMOTE_AHEAD" -ne 0 ]; then
        fail "Overleaf changed before the direct edit. Integrate remote changes first."
    fi

    DIRECT_PROMPT="$RUN_DIR/direct-edit-prompt.txt"
    PAPER_RESULT="$RUN_DIR/paper-agent-result.md"

    cat > "$DIRECT_PROMPT" <<'EOF'
TECHNICAL EDIT AUTHORIZED.

The user explicitly authorized a local technical correction.

Follow AGENTS.md and PAPER_CONTEXT.md if it exists.

This issue has been classified as DIRECT_EDIT because the intended
correction is already determined from established manuscript context.

Do NOT conduct new research.

Do NOT introduce:
- new assumptions;
- new lemmas;
- new arguments;
- new claims;
- model changes.

Inspect only enough surrounding manuscript context to confirm the
specified correction.

Make the smallest possible correction.

All changed or newly introduced prose must be visibly wrapped according
to the existing \sj{...} policy in AGENTS.md.

Do not modify unrelated text.

Do not commit.
Do not push.
Do not pull.
Do not merge.
Do not change branches.

After editing:

1. inspect git diff;
2. verify the correction matches established manuscript definitions;
3. verify all changed prose is marked with \sj{...};
4. report exactly what changed.

The confirmed technical issue follows:

------------------------------------------------------------
EOF

    cat "$RUN_DIR/problem.txt" >> "$DIRECT_PROMPT"

    (
        cd "$PAPER_REPO"
        codex  exec - < "$DIRECT_PROMPT"
    ) > "$PAPER_RESULT"

    separator "Paper Agent direct-edit result"

    cat "$PAPER_RESULT"

    # Verify diff

    git -C "$PAPER_REPO" diff --check

    separator "Changed files"

    git -C "$PAPER_REPO" diff --name-only

    separator "Diff"

    git -C "$PAPER_REPO" diff

    # Compile

    separator "Compiling manuscript"

    (
        cd "$PAPER_REPO"

        latexmk \
            -pdf \
            -interaction=nonstopmode \
            -halt-on-error \
            main.tex
    )

    echo
    echo "Compilation succeeded."

    separator "DIRECT EDIT COMPLETE"

    echo "Nothing has been committed."
    echo "Nothing has been pushed."
    echo
    echo "Review:"
    echo
    echo "  cd \"$PAPER_REPO\""
    echo "  git diff"
    echo "  open main.pdf"

    exit 0
fi

# ============================================================
# QUICK VERIFY FLAG
# ============================================================

QUICK_MODE=false

if [ "$TRIAGE_MODE" = "QUICK_VERIFY" ]; then
    QUICK_MODE=true
fi


# ============================================================
# STAGE 1
# PAPER AGENT EXTRACTS RELEVANT MANUSCRIPT CONTEXT
# ============================================================

separator "STAGE 1 — Paper Agent extracting research context"

HANDOFF_PROMPT="$RUN_DIR/handoff-prompt.txt"
HANDOFF_RESULT="$RUN_DIR/research-handoff.md"

cat > "$HANDOFF_PROMPT" <<'EOF'
READ ONLY.

Do not modify any file.

You are the Paper Editor Agent for this manuscript.

Follow AGENTS.md and PAPER_CONTEXT.md if PAPER_CONTEXT.md exists.

A technical problem must be handed to a separate Research Agent.

Your task is NOT to solve the problem.

Instead, search the manuscript and extract the minimal but sufficient
technical context required for a Research Agent to investigate it.

Do not invent assumptions.
Do not repair arguments.
Do not change the manuscript.
Preserve the manuscript's exact mathematical notation.

Produce a structured output with exactly these sections:

# RESEARCH HANDOFF PACKET

## Technical Issue

State the technical issue precisely.

## Exact Location

Identify the relevant:
- appendix or section;
- subsection;
- paragraph;
- case;
- definition;
- lemma;
- theorem;
- equation;
- algorithm;

as applicable.

## Relevant Definitions

Include only definitions directly needed to understand the problem.

Preserve exact notation.

## Relevant Assumptions

Identify all assumptions that may matter, including when applicable:

- synchrony assumptions;
- network-delay assumptions;
- adversary assumptions;
- information / foresight assumptions;
- timing assumptions;
- independence assumptions;
- conditioning;
- protocol rules.

Do not infer assumptions that are not present in the manuscript.

## Relevant Notation

Define every symbol needed to understand the technical issue.

## Relevant Prior Results

Identify lemmas, propositions, equations, definitions, or previously
established claims on which this argument depends.

## Local Argument

Explain the exact proof, transition, or derivation step where the
technical issue occurs.

Preserve the intended mathematical meaning.

## Dependencies Elsewhere

Identify other results in the manuscript that:

- depend on this step;
- constrain its meaning;
- use the same definition;
- use the same transition;
- rely on the same assumption.

## Missing or Ambiguous Context

If anything required to solve the problem is missing or ambiguous,
state it here.

Do not resolve the ambiguity yourself.

## Precise Open Question

Formulate as precisely as possible what must be:

- proved;
- disproved;
- derived;
- clarified; or
- corrected.Do not attempt to answer the question.

The user's technical problem is below.

------------------------------------------------------------
EOF

cat "$RUN_DIR/problem.txt" >> "$HANDOFF_PROMPT"

(
    cd "$PAPER_REPO"
    codex exec - < "$HANDOFF_PROMPT"
) > "$HANDOFF_RESULT"

if [ ! -s "$HANDOFF_RESULT" ]; then
    fail "Paper Agent produced an empty Research Handoff Packet."
fi

echo "Research Handoff Packet created:"
echo
echo "$HANDOFF_RESULT"
echo

cat "$HANDOFF_RESULT"


# ============================================================
# STAGE 2
# RESEARCH AGENT INVESTIGATES
# ============================================================

# ============================================================
# STAGE 2
# RESEARCH AGENT INVESTIGATES
# ============================================================

RESEARCH_PROMPT="$RUN_DIR/research-prompt.txt"
RESEARCH_RESULT="$RUN_DIR/research-result.md"


# ============================================================
# QUICK VERIFY PATH
# ============================================================

if [ "$TRIAGE_MODE" = "QUICK_VERIFY" ]; then

    separator "STAGE 2 — Quick technical verification"

    cat > "$RESEARCH_PROMPT" <<'EOF'
You are the Research Agent.

This is a QUICK technical verification, not a full research project.

Follow the AGENTS.md instructions in this research repository.

A Paper Editor Agent has provided a Research Handoff Packet below.

Your task is to answer one localized mathematical question efficiently
and rigorously.

Do not edit the Overleaf manuscript.

Do not perform broad research exploration.

Required workflow:

1. State exactly what must be checked.

2. Identify the existing manuscript assumptions that are relevant.

3. Give the shortest rigorous derivation needed to verify or reject
   the local claim.

4. Check signs, indices, ranges, conditioning, dependencies, and timing
   assumptions when applicable.

5. Check the most relevant boundary case.

6. Attempt one direct counterexample check.

Do NOT:

- redesign the model;
- introduce new state variables;
- propose new protocol variants;
- explore unrelated generalizations;
- introduce new assumptions unless necessary to explain why the claim
  cannot currently be verified;
- generate multiple alternative proofs unless the first argument fails;
- turn this into a broader research problem unnecessarily.

At the VERY BEGINNING of your response, output exactly one of:

STATUS: READY_FOR_PAPER

or

STATUS: NOT_READY

Use STATUS: READY_FOR_PAPER only when the localized technical issue
has been rigorously resolved using existing manuscript assumptions.

Use STATUS: NOT_READY if:
- an assumption is missing;
- the claim cannot be verified locally;
- a counterexample may exist;
- a proof gap remains;
- or the problem requires substantial new research.

Then use exactly this structure:

# QUICK VERIFICATION

## Question

State exactly what is being verified.

## Relevant Assumptions

List only assumptions actually used.

## Verification

Give the shortest rigorous argument.

## Boundary / Sign / Index Checks

Check the relevant edge cases, signs, and index ranges.

## Counterexample Check

State what counterexample was tested and the outcome.

## Conclusion

State clearly whether the proposed correction is justified.

## VALIDATED RESULT FOR PAPER

If STATUS is READY_FOR_PAPER, provide:

- the exact technical correction;
- the mathematical reason;
- any limitation;
- what the Paper Editor should change.

If STATUS is NOT_READY, leave this section empty and explain why the
problem should be escalated to FULL_RESEARCH.

The Research Handoff Packet follows.

------------------------------------------------------------
EOF

    cat "$HANDOFF_RESULT" >> "$RESEARCH_PROMPT"

    (
        cd "$RESEARCH_REPO"

        codex \
             \
            -c 'model_reasoning_effort="medium"' \
            exec - < "$RESEARCH_PROMPT"
    ) > "$RESEARCH_RESULT"


# ============================================================
# FULL RESEARCH PATH
# ============================================================

elif [ "$TRIAGE_MODE" = "FULL_RESEARCH" ]; then

    separator "STAGE 2 — Full Research Agent investigation"

    cat > "$RESEARCH_PROMPT" <<'EOF'
You are the Research Agent.

Follow the AGENTS.md instructions in this research repository.

A Paper Editor Agent has provided a Research Handoff Packet below.

Your job is to investigate the technical problem rigorously.

Do NOT edit the Overleaf manuscript.

You may create or update research notes inside this research workspace
if useful.

Required research workflow:

1. Restate exactly what must be established.

2. List the assumptions actually needed.

3. Separate:
   - established facts;
   - manuscript assumptions;
   - derived conclusions;
   - conjectures;
   - heuristic intuition;
   - unresolved gaps.

4. Attempt a rigorous proof or derivation.

5. Independently attempt to construct a counterexample.

6. Test relevant boundary cases and extreme parameter values.

7. Check all index ranges carefully.

8. Check conditioning and independence assumptions.

9. Check for hidden dependence on future information.

10. Check whether a Markov property or sufficient-state assumption
    is implicitly required.

11. Check whether the proposed argument agrees with all relevant
    manuscript definitions supplied in the handoff.

12. Perform an adversarial verification pass against your own result.

Do not call a result proved merely because the argument appears
plausible.

At the VERY BEGINNING of your final response, output exactly one of:

STATUS: READY_FOR_PAPER

or

STATUS: NOT_READY

Use STATUS: READY_FOR_PAPER only when the result survives your
adversarial verification and can be stated precisely with its required
assumptions.

Use STATUS: NOT_READY if any mathematical gap, ambiguity, missing
assumption, or unresolved counterexample remains.

Then use this structure:

# RESEARCH RESULT

## Problem

## Assumptions

## Known Facts

## Claim or Finding

## Proof / Derivation

## Counterexample Search

## Boundary-Case Checks

## Conditioning / Independence Checks

## State / Information Checks

## Adversarial Verification

## Remaining Gaps

## VALIDATED RESULT FOR PAPER

If STATUS is READY_FOR_PAPER:

Provide a concise, self-contained package containing:

- exact assumptions;
- exact claim;
- proof or derivation;
- limitations;
- what the Paper Editor should change in the manuscript.

If STATUS is NOT_READY:

Leave VALIDATED RESULT FOR PAPER empty and explain exactly what remains
unresolved.

The Research Handoff Packet follows.

------------------------------------------------------------
EOF

    cat "$HANDOFF_RESULT" >> "$RESEARCH_PROMPT"

    (
        cd "$RESEARCH_REPO"

        codex \
             \
            exec - < "$RESEARCH_PROMPT"
    ) > "$RESEARCH_RESULT"


# ============================================================
# INVALID MODE
# ============================================================

else

    fail "Unexpected TRIAGE_MODE in Stage 2: $TRIAGE_MODE"

fi


# ============================================================
# CHECK RESEARCH RESULT
# ============================================================

if [ ! -s "$RESEARCH_RESULT" ]; then
    fail "Research Agent produced an empty result."
fi

separator "Research Agent result"

cat "$RESEARCH_RESULT"

# ============================================================
# STOP IF RESEARCH AGENT IS NOT READY
# ============================================================

if ! grep -q '^STATUS: READY_FOR_PAPER' "$RESEARCH_RESULT"; then
    separator "STOPPED — research result is not ready"

    echo "The Research Agent did not mark the result READY_FOR_PAPER."
    echo
    echo "No manuscript files have been modified."
    echo
    echo "Research result saved at:"
    echo
    echo "$RESEARCH_RESULT"
    echo
    exit 0
fi


# ============================================================
# HUMAN APPROVAL GATE
# ============================================================

separator "HUMAN REVIEW REQUIRED"

echo "The Research Agent marked this result READY_FOR_PAPER."
echo
echo "Please read the result above carefully."
echo
echo "This status is NOT proof that the mathematics is correct."
echo
echo "You remain the final technical reviewer."
echo

read -r -p \
"Allow AI 1 to integrate this result into the manuscript? [y/N] " \
ANSWER

case "$ANSWER" in
    y|Y|yes|YES)
        echo
        echo "Approved."
        ;;
    *)
        echo
        echo "Stopped before manuscript modification."
        echo
        echo "No paper files were changed."
        exit 0
        ;;
esac


# ============================================================
# CHECK OVERLEAF AGAIN
# ============================================================

separator "Checking Overleaf again before writing"

git -C "$PAPER_REPO" fetch overleaf

REMOTE_AHEAD="$(
    git -C "$PAPER_REPO" rev-list \
        --right-only \
        --count \
        HEAD...overleaf/master
)"

if [ "$REMOTE_AHEAD" -ne 0 ]; then
    echo "STOP."
    echo
    echo "Overleaf changed while the Research Agent was working."
    echo
    echo "There are now $REMOTE_AHEAD new remote commit(s)."
    echo
    echo "No manuscript changes will be made."
    echo
    echo "Integrate the advisor's latest Overleaf changes first,"
    echo "then rerun this workflow."
    exit 1
fi

echo "Overleaf is still synchronized."


# ============================================================
# STAGE 3
# PAPER AGENT INTEGRATES VALIDATED RESULT
# ============================================================

separator "STAGE 3 — Paper Agent integrating validated result"

INTEGRATE_PROMPT="$RUN_DIR/integrate-prompt.txt"
PAPER_RESULT="$RUN_DIR/paper-agent-result.md"

cat > "$INTEGRATE_PROMPT" <<'EOF'
EDIT.

The user explicitly approved integrating the Research Agent result
below into the manuscript.

Follow AGENTS.md and PAPER_CONTEXT.md if PAPER_CONTEXT.md exists.

The Research Agent is responsible for technical exploration.

You are responsible only for correctly integrating the approved
result into the manuscript.

Do not independently strengthen, weaken, extend, reinterpret, or
generalize the mathematical result.

Locate the relevant manuscript passage yourself using the supplied
Research Handoff Packet and validated result.

Make the smallest change needed to resolve the technical issue.

IMPORTANT EDITING REQUIREMENTS:

1. Preserve all unaffected manuscript text.

2. Every new or rewritten piece of manuscript prose introduced by
   you must follow the existing \sj{...} marking policy in AGENTS.md.

3. Do not unnecessarily wrap unchanged surrounding text in \sj{...}.

4. Preserve:
   - labels;
   - references;
   - citation keys;
   - macros;
   - equation environments;
   - theorem environments;
   - notation;

   unless the validated result explicitly requires an approved
   technical change.

5. Do not make unrelated editorial changes.

6. If the validated result conflicts with the actual manuscript
   context or cannot be integrated without introducing an additional
   technical assumption that was not validated:

   STOP.

   Do not force an edit.

   Report:

   [TECHNICAL ISSUE]

7. Do not commit.

8. Do not push.

9. Do not pull.

10. Do not merge.

11. Do not change branches.

After editing:

- inspect git diff;
- verify every AI-written prose edit is visibly marked with \sj{...};
- verify no unrelated text changed;
- summarize exactly what was changed;
- identify any remaining technical concern.

The Research Agent result follows.

------------------------------------------------------------
EOF

cat "$RESEARCH_RESULT" >> "$INTEGRATE_PROMPT"

(
    cd "$PAPER_REPO"
    codex  exec- < "$INTEGRATE_PROMPT"
) > "$PAPER_RESULT"

separator "Paper Agent integration report"

cat "$PAPER_RESULT"


# ============================================================
# VERIFY THAT SOMETHING ACTUALLY CHANGED
# ============================================================

if git -C "$PAPER_REPO" diff --quiet; then
    separator "No manuscript changes detected"

    echo "The Paper Agent did not modify tracked manuscript files."
    echo
    echo "Review its report here:"
    echo
    echo "$PAPER_RESULT"
    exit 0
fi


# ============================================================
# GIT DIFF SAFETY CHECK
# ============================================================

separator "Running Git diff checks"

git -C "$PAPER_REPO" diff --check

echo
echo "Changed files:"
git -C "$PAPER_REPO" diff --name-only

echo
echo "Diff summary:"
git -C "$PAPER_REPO" diff --stat


# ============================================================
# COMPILE PAPER
# ============================================================

separator "Compiling manuscript"

(
    cd "$PAPER_REPO"
    latexmk \
        -pdf \
        -interaction=nonstopmode \
        -halt-on-error \
        main.tex
)

echo
echo "LaTeX compilation succeeded."


# ============================================================
# INSPECT LOG WARNINGS
# ============================================================

if command -v rg >/dev/null 2>&1 && \
   [ -f "$PAPER_REPO/main.log" ]; then

    separator "Relevant LaTeX warnings"

    (
        cd "$PAPER_REPO"

        rg -ni \
        "undefined|multiply defined|overfull|missing|citation" \
        main.log \
        || true
    )
else
    echo
    echo "Skipping rg log scan because ripgrep or main.log"
    echo "is unavailable."
fi


# ============================================================
# FINAL SAFETY CHECK:
# OVERLEAF MUST STILL NOT HAVE NEW COMMITS
# ============================================================

separator "Final Overleaf safety check"

git -C "$PAPER_REPO" fetch overleaf

REMOTE_AHEAD="$(
    git -C "$PAPER_REPO" rev-list \
        --right-only \
        --count \
        HEAD...overleaf/master
)"

if [ "$REMOTE_AHEAD" -ne 0 ]; then
    echo
    echo "WARNING:"
    echo
    echo "Overleaf received new changes after the manuscript edit."
    echo
    echo "DO NOT PUSH."
    echo
    echo "Your local edits remain intact."
    echo
    echo "Integrate the remote changes manually before committing/pushing."
else
    echo "No new Git-visible Overleaf changes detected."
fi


# ============================================================
# FINAL REPORT
# ============================================================

separator "WORKFLOW COMPLETE"

echo "The agents have completed the research handoff and paper edit."
echo
echo "NOTHING has been committed."
echo "NOTHING has been pushed to Overleaf."
echo
echo "Review manually:"
echo
echo "  cd \"$PAPER_REPO\""
echo "  git diff"
echo "  open main.pdf"
echo
echo "If the edit is correct, your normal manual workflow is:"
echo
echo "  git fetch overleaf"
echo "  git add <specific manuscript files>"
echo "  git commit -m \"Resolve technical issue\""
echo
echo "  git fetch overleaf"
echo "  git rev-list --left-right --count HEAD...overleaf/master"
echo
echo "Make sure the RIGHT number is 0."
echo
echo "Then push:"
echo
echo "  git push overleaf ai-paper-editor:master"
echo
echo
echo "All workflow artifacts are saved in:"
echo
echo "  $RUN_DIR"
echo
echo "Files include:"
echo
echo "  problem.txt"
echo "  research-handoff.md"
echo "  research-result.md"
echo "  paper-agent-result.md"
echo
