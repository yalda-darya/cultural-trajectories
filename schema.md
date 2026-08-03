# Data schema

## Elicitation record (one JSON object per line, per API call)

Files: `data/raw/<provider>_<model>/results_<ISO3>_<provider>_<model>.jsonl`.
One record per (country × condition × item × wave × replicate).

| Field | Type | Notes |
|-------|------|-------|
| `call_id` | str | Stable hash of the cell + replicate index. Basis of idempotent resume. |
| `ts` | float | Unix timestamp of the call. |
| `provider` | str | `anthropic` \| `openai` \| `google` \| `together` (\| `meta`, excluded). |
| `model` | str | API model id. |
| `country` | str | ISO3. |
| `condition` | str | `C0` (no year anchor) \| `C1` \| `C2` (year-anchored). |
| `item_id` | str | One of the ten core indicators (e.g. `F118`, `Y002`, `CARDSORT`). |
| `item_type` | str | `A` single-scale distribution · `B` card sort · `C` ordered pairs. |
| `wave` | int | WVS wave 4–7. |
| `year` | int/null | Fieldwork year filled into the C2 prompt; null for C0/C1. |
| `replicate` | int | 0…k−1. |
| `temperature` | null | No temperature sent; provider default used. |
| `prompt_version` | str | `2026-07-20.1`. |
| `system_hash` | str | Hash of the scaffold/system prompt, for drift detection. |
| `user_prompt` | str | The exact assembled user turn. |
| `raw_response` | str/null | Raw model text (null on failure). |
| `parsed` | obj/null | Parsed distribution; renormalized for `OK`/`NORMALIZED`, raw for `SUM_OUT_OF_RANGE`. |
| `flag` | str | See taxonomy below. |
| `attempts` | int | API attempts made (content + transient retries). |
| `usage` | obj/null | `input_tokens`, `output_tokens`; `thoughts_tokens` (Gemini) / `reasoning_tokens` (Meta) where present. |
| `api_error` | str/null | Error string on failure, else absent/null. |

## Flag taxonomy

**Usable** (enter the estimand): `OK`, `NORMALIZED`, `SUM_SOFT_OVER`.

| Flag | Meaning | Usable? |
|------|---------|---------|
| `OK` | Type A/C sum within 0.02 of 1 (renormalized); or card sort within soft limit. | ✅ |
| `NORMALIZED` | Type A/C sum within the normalize band (A: 0.10, C: 0.30); rescaled to 1. | ✅ |
| `SUM_SOFT_OVER` | Card sort (Type B) sum above the soft limit but ≤ hard limit. | ✅ |
| `SUM_OUT_OF_RANGE` | Type A/C sum beyond the normalize band; raw values retained but dropped from estimand. | ❌ |
| `SUM_HARD_OVER` | Card sort sum above the hard limit. | ❌ |
| `VALUE_OUT_OF_RANGE` | A value outside its allowed range (A/C: [0,1]; B: [0,100]). | ❌ |
| `WRONG_KEYS` | Returned keys do not match the item's expected option set. | ❌ |
| `MALFORMED_JSON` | Response could not be parsed as the expected JSON object. | ❌ (retry-worthy) |
| `REFUSAL` | Model declined to answer. | ❌ (retry-worthy) |
| `EMPTY` | No usable content / failed call (usually paired with `api_error`). | ❌ (retry-worthy) |

**Stopping rule:** inspect if any item-type exceeds ~5% non-usable in a country, or
if any refusal appears.

**QC scripts** (`scripts/`):
- `qc_completeness.py` — per-country coverage + failed-row scan across a leg.
- `qc_strip_failed.py` — drops `EMPTY`/`REFUSAL`/`MALFORMED_JSON` rows so a resume refills them (their `call_id`s are removed).
- `reflag_type_c.py` — applies the 0.30 Type C normalize band uniformly to stored records (raw values preserved; no re-run).
