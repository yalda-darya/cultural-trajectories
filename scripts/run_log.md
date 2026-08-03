# Run log

Provenance record of how the elicitation data came to be: what ran, and every
model-specific incident or deviation. This is the companion to `model_panel.md`
(which records the *settings*); this file records the *events*. If a reviewer or
future-you asks "why does Gemini's Turkey file have a `_PREPATCH` sibling?", the
answer is here.

All models: single-pass, **k = 10** default-temperature draws, no temperature sent,
conditions C0/C1/C2, English, `PROMPT_VERSION 2026-07-20.1`, 40 countries / 134
country-waves. Per-model recommended k (at target-SEM 0.01) is recorded below but was
**not** used; a uniform k = 10 was run, with the option to top up idempotently later.

---

## Claude Opus 4.8 (`anthropic`)
- Pilot on Turkey (k=5) → recommended k = 10 → **locked k = 10**. Canary: Argentina, 100% usable.
- Single-pass: native (no thinking requested).
- Incidents: a few scattered transient failed rows across countries; cleaned with `qc_strip_failed.py` and refilled on resume.
- Ran under the *original* runner (Type A/C band 0.10). **Retroactively reflagged** to the 0.30 Type C band (see cross-cutting note).

## GPT-5.5 (`openai`)
- Turkey pilot → recommended k = 21. Ran at **k = 10** (uniform-k decision).
- Single-pass: `reasoning_effort="none"`; verified reasoning tokens ≈ 0, output ≈ 51 tokens/call.
- Uses `max_completion_tokens` (not `max_tokens`).
- Incidents: scattered transient failed rows, cleaned and refilled. Reflagged to 0.30 Type C band retroactively.

## Gemini 3.6 Flash (`google`)
- Turkey pilot → recommended k = 24. Ran at **k = 10**.
- Single-pass: `thinking_level="minimal"` — Gemini 3 Flash has **no true thinking-off**; minimal is the floor. Pilot measured ~0 thought tokens in practice.
- Incident — **thinking config bug:** first client used `thinking_budget=0`, which Gemini 3.x rejects (HTTP 400 on every call). Fixed to `thinking_level="minimal"`. The broken pilot file was retired as `*_BROKEN_thinkingbudget.jsonl`.
- Incident — **Type C overshoot:** Qwen/Gemini render the Type C ordered-pairs item (Y002) with sums 1.10–1.28. Under the old 0.10 band these were dropped (Type C ~88% usable, tripping the ~5% stopping rule). Decision: widen the Type C normalize band to **0.30** and renormalize. Applied here first, then uniformly to all legs. Turkey pilot reflagged; its pre-band copy kept as `*_PREPATCH.jsonl`.
- Incident — **daily quota:** free/low tier caps `generate_requests_per_model_per_day` at 10,000. At ~590 calls/country the run hit the cap ~country 20 (a 429 mid-PHL) and again on later days; completed as a **multi-day resume**. Each resume: strip failed rows → re-run. No data lost (idempotent).
- Turkey was re-run fresh at k=10 under the patched runner (its earlier session file retired).

## Qwen3.6-Plus (`together`, Alibaba)
- Replaces the originally-planned Meta/Llama open-weights slot (see below). Chosen as a current-generation open model.
- Turkey pilot → recommended k = **60** (noisiest model; loudest cells are the charged justifiability items and G006/E018). Ran at **k = 10**; final-k decision deferred to the ground-truth stage, where G006/E018 movement settles whether top-up is needed.
- Single-pass: `chat_template_kwargs={"enable_thinking": false}`; verified no `<think>` blocks, output ≈ 72 tokens/call.
- Incident — **streaming required:** the model returns HTTP 400 unless `stream=true`. Client accumulates streamed chunks and reads usage from the final chunk.
- Incidents: TUR (1) and IRN (1) transient failed rows, cleaned and refilled.

---

## Meta — evaluated, EXCLUDED
- Intended as the Meta / open-weights entry. Two dead ends:
  - **Llama 4 Maverick** (frontier open): removed from Together serverless (dedicated-endpoint only); the Llama line is discontinued (replaced by Muse Spark, April 2026).
  - **Muse Spark 1.1** (Meta's current model): reasoning-**only**. `reasoning_effort` floor is `minimal` (API rejects `none`). Turkey pilot at `minimal` produced ~348k reasoning tokens (~655 output tokens/call vs. ~50–70 for single-pass legs) — does not meet the elicitation condition.
- Decision: **exclude Meta** from the main panel. Its non-reasoning option (legacy Llama 3.3 70B) is two generations old and redundant with Qwen on openness. Documented rather than forced in. Pilot artifacts kept under `data/pilot/` if the reasoning-vs-single-pass contrast is pursued later.

---

## Cross-cutting decisions
- **Uniform k = 10** across all four models (draw budget held constant; precision varies — report per-model replicate SEMs). Per-model recommended k: Claude 10 / GPT 21 / Gemini 24 / Qwen 60 at SEM 0.01. Top-up is a resume, not a re-run.
- **Type C 0.30 normalize band** applied uniformly to all four legs. Claude and GPT (run under the old 0.10-band runner) were reflagged retroactively via `reflag_type_c.py`; raw values are preserved in the JSONL, so no re-run was needed.
- **No temperature** sent to any model (each provider's default used), keeping the "default-temperature draws" estimand parallel across the panel.
- QC per leg: `qc_completeness.py` → "all 40 complete and clean" before the leg was considered done.
