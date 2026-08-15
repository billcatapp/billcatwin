# CLAUDE.md — Project Rules

## Project context
- This is BillCat: a Flutter desktop app for Windows (POS billing software for small retail shops in India).
- Target platform is Windows only. Do not add Android-, iOS-, or web-specific code.
- Distribution: Flutter Windows release build, packaged as MSIX and code-signed. Do not touch build or packaging config unless that is the task.

## Scope control — most important rules
- NEVER modify any code, feature, or logic without my explicit consent. Work ONLY on exactly what I asked for in the current request — nothing extra, nothing "while you're at it."
- If completing my request seems to require changing any code or behavior I did not mention, STOP and ask me first. My approval in one request does not carry over to the next.
- Only modify files explicitly named in my request.
- If other files must change for the code to compile or work, STOP, list those files, and ask before editing them.
- Make the smallest change that completes the task. Prefer minimal diffs.
- Never refactor, "improve," or clean up code that is not part of the task, even if it looks wrong, outdated, or messy.
- Never reformat existing code, reorder imports, or change indentation on lines you are not otherwise editing.
- Do not rename variables, functions, classes, files, or folders unless explicitly asked.
- Do not delete existing code, files, or comments unless deletion is the task.
- Do not add, remove, or upgrade packages in pubspec.yaml without asking first.
- Do not create new files unless the task clearly requires it. Ask first if unsure.

## Logic preservation — do not change behavior
- Never change what existing code DOES unless changing that behavior is explicitly the task.
- Do not "fix" conditions, calculations, or formulas that look wrong to you. Flag them and ask — do not correct them yourself.
- When editing a function, preserve its exact behavior: same comparison operators (>, >=, ==), same order of operations, same rounding, same default values, same return values.
- Do not modify if/else branches, loop bounds, or early returns that are outside the specific change requested.
- Do not change validation rules, null checks, or error handling unless asked.
- Do not change existing function signatures, parameter defaults, or return types. If a new need arises, add a new function instead and ask.
- Never silently change constants, rates, thresholds, or magic numbers (e.g. tax percentages, rounding rules, limits).
- When a bug fix requires logic changes beyond the exact bug, explain the change and its side effects first, then wait for approval.
- If I ask for a refactor, the refactored code must behave identically to the original. Any behavior difference must be called out explicitly before you apply it.

## Protected zones — treat as read-only
- GST/tax calculation, rounding, and invoice total logic.
- Invoice numbering and bill generation.
- Discount and pricing logic.
- Stock/inventory quantity math.
- Payment status and UPI handling.
- Database schema and migrations.
- Cloud/local sync logic: connectivity_service.dart, the sync/merge/reconcile and soft-delete functions in local_db_service.dart, realtime subscriptions, and Supabase RLS policies. This system is finalized and verified (July 2026) — do not touch it without my explicit permission.
- Never modify code in these areas unless my request names them directly. If a task seems to require touching them, stop and confirm first.

## When in doubt
- If my request is ambiguous, ask one clarifying question instead of guessing.
- If you believe extra changes are genuinely necessary, propose them and wait for my approval. Do not just make them.

## Planning
- For any change that touches 3 or more files, or anything involving billing logic, invoicing, GST calculations, database, or payments, present a plan first and wait for my approval before editing anything.

## After every task
- List every file you modified and summarize what changed in each one.
- If you noticed problems outside the task scope, mention them at the end — do not fix them yourself.
