# Model panel

All models were run in a **single-pass (non-reasoning)** configuration, at **k = 10**
default-temperature draws per cell, with **no temperature parameter sent** (each
provider's default is used). The estimand is the mean stated distribution over the
ten draws. The goal of the single-pass condition is that the elicited object is the
model's *stated* distribution, not one it reasoned its way to — a deliberated answer
can reconcile a distribution against what "should" be true and so measure a different
construct.

Because each provider exposes reasoning differently, "single-pass" was reached by a
different mechanism per model. This table is the honest core of the methods section.

| Lab | Model (API id) | Provider tag | Weights | Single-pass mechanism | Verified off? | Recommended k @ SEM 0.01 | k run |
|-----|----------------|--------------|---------|-----------------------|---------------|--------------------------|-------|
| Anthropic | `claude-opus-4-8` | `anthropic` | closed | native — no thinking requested | n/a (no thinking mode) | 10 | 10 |
| OpenAI | `gpt-5.5` | `openai` | closed | `reasoning_effort="none"` | yes — reasoning tokens ≈ 0 | 21 | 10 |
| Google | `gemini-3.6-flash` | `google` | closed | `thinking_level="minimal"` | pilot showed thought tokens ≈ 0, but `minimal` is a floor, **not a true off** | 24 | 10 |
| Alibaba | `Qwen/Qwen3.6-Plus` | `together` | open | `chat_template_kwargs={"enable_thinking": false}` (streaming) | yes — no `<think>` blocks, output tokens ≈ others | 60 | 10 |

## Two caveats to state in the paper

1. **k is uniform at 10, but per-model precision is not.** Applying the same
   target-SEM 0.01 rule to each model's Turkey pilot recommended k = 10 / 21 / 24 / 60
   respectively (Claude / GPT / Gemini / Qwen). Running all four at k = 10 holds the
   *draw budget* constant and lets *precision* vary: the noisier models (notably Qwen,
   whose loudest cells are the charged justifiability items and G006/E018) carry wider
   replicate intervals. Report per-model replicate SEMs alongside results. The draws
   are top-up-able (the runner appends idempotently), so tightening any model to its
   recommended k later is a resume, not a re-run.

2. **Gemini's floor is "minimal," not "none."** Gemini 3 Flash has no true
   thinking-off; `thinking_level="minimal"` is the closest setting. The Turkey pilot
   measured ~0 thinking tokens, so in practice it behaved single-pass, but this is a
   floor and should be recorded as such rather than as equivalent to the others' zero.

## Meta — evaluated and excluded

Meta's current model, **Muse Spark 1.1**, is a reasoning model whose reasoning
**cannot be disabled**: `reasoning_effort` runs `minimal`→`xhigh`, and `minimal` is
the floor (the API rejects `none`). A Turkey pilot at `minimal` produced ~590
reasoning tokens per call (≈ 655 output tokens/call vs. ~50–70 for the single-pass
legs), confirming it does not meet the elicitation condition. Meta's non-reasoning
option is the discontinued Llama line (Llama 3.3 70B is two generations old and, on
the openness axis, redundant with Qwen). Meta is therefore excluded from the main
panel. If a reasoning-vs-single-pass contrast is pursued, Muse Spark belongs in that
separate sub-analysis with its own framing and k — not as a peer here.

## Normalization

Type A (single-scale distributions) use a sum-normalization band of 0.10; Type C
(ordered-pair distributions, item Y002) use a wider band of 0.30, because the models
render ordered-pair distributions as loosely-normalized structure that is rescaled
rather than dropped. The band was applied **uniformly across all four models** via
`scripts/reflag_type_c.py` (raw values are preserved in the JSONL regardless of flag,
so the policy is applied at analysis time without re-running). Report each model's
Type C non-usable / renormalized rate as a measurement-quality observation.
