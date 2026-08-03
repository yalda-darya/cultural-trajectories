#!/usr/bin/env python3
"""
Elicitation runner (Turkey-first pilot harness).

Reads the frozen item bank (item_bank_W4toW7.json) and the frozen year spine
(c2_year_spine.csv), builds the elicitation call manifest, calls a model, parses
the JSON distribution the model returns, validates it, flags malformed / refusal
output, retries transient failures, and appends one provenance record per
completion to a JSONL log. Reruns are idempotent: completed call_ids are skipped.

WORKFLOW (do these in order):
  1. Dry run — assemble every prompt, dump to a preview file, print manifest size.
       python frozen_mirrors_runner.py --dry-run --country TUR
     Read prompts_preview.txt end to end before spending a cent.
  2. Mock run — exercise parse/validate/logging with a fake client, no network.
       python frozen_mirrors_runner.py --mock --country TUR
  3. Live pilot — set ANTHROPIC_API_KEY (or your provider key) and run for real.
       python frozen_mirrors_runner.py --country TUR --model claude-opus-4-8

KEY DECISIONS (surfaced, not silently defaulted):
  - CANONICAL_WAVE (=7): wording used for the wave-agnostic conditions C0/C1,
    since those carry no year. The wave-varying items (A008, card sort) need one
    instrument; the most recent is the natural default. Documented, not implicit.
  - TEMPERATURE / N_SAMPLES [UPDATED 2026-07-20]: the frontier Anthropic tier
    (Opus 4.8, Sonnet 5) returns a 400 on any non-default temperature, so temp-0
    is not available on the audited model. Primary estimand is therefore the
    MEAN stated distribution over k default-temperature draws per cell. The prompt
    elicits a full distribution in one shot, so temperature only jitters the
    reported numbers, not whether a distribution is returned; the k-draw mean is
    the estimand, not a single arbitrary point. Reliability still comes from the
    perturbation arms (paraphrase, option order, C3/P), which measure meaningful
    invariances. Set k FROM THE PILOT: run the same cell k times (--n-samples 5;
    call_id includes the replicate index, so these are real draws, not cache
    hits), measure per-cell dispersion across replicates (analyze_pilot.py), and
    pick k so the SEM of the per-cell mean is acceptable, and set it as the run default.
    DEFAULT_TEMPERATURE = None sends NO temperature (required for Opus 4.8 /
    Sonnet 5); pass --temperature 0 only to a temp-accepting pre-4.7 model, where
    it flows through and a loud 400 no longer masks a silently wrong number.
  - Validation tolerances (SUM_TOL etc.) below.
"""

import argparse, csv, hashlib, json, os, sys, time
from dataclasses import dataclass, asdict, field
from pathlib import Path

# ---------------------------------------------------------------------------
# Config / constants
# ---------------------------------------------------------------------------

PROMPT_VERSION = "2026-07-20.1"   # bump when scaffold/bank wording changes -> invalidates cache
CANONICAL_WAVE = 7                # wording for wave-agnostic conditions (C0, C1)
DEFAULT_TEMPERATURE = None       # frontier tier rejects explicit temperature; send none, average over k draws
DEFAULT_N_SAMPLES = 1            # replicates only for the determinism probe (raise deliberately)
DEFAULT_MAX_TOKENS = 1024
SUM_TOL = 0.02                    # Type A / C: |sum - 1| tolerance before normalize
NORMALIZE_BAND = 0.10            # Type A: within this, normalize + flag; beyond, reject
NORMALIZE_BAND_C = 0.30         # Type C (ordered pairs): wider band — model renders these
                                # as loosely-normalized structure; rescale rather than drop
CARDSORT_SOFT = 500              # <= this is fine (choose up to five)
CARDSORT_HARD = 700             # > this is discarded
MAX_CONTENT_RETRIES = 3          # malformed JSON -> re-ask
MAX_API_RETRIES = 5              # transient API/network -> backoff

# ISO3 -> ({country} display, {nationality}). {country} fills "adults living in
# {country}"; {nationality} fills G006 "How proud are you to be {nationality}?",
# so each demonym must read correctly after "to be" (noun demonyms carry "a").
# HKG and TWN display/demonym are conventions — adjust if your write-up prefers others.
COUNTRY_INFO = {
    "ARG": ("Argentina", "Argentine"),
    "AUS": ("Australia", "Australian"),
    "BRA": ("Brazil", "Brazilian"),
    "CAN": ("Canada", "Canadian"),
    "CHL": ("Chile", "Chilean"),
    "CHN": ("China", "Chinese"),
    "COL": ("Colombia", "Colombian"),
    "CYP": ("Cyprus", "Cypriot"),
    "DEU": ("Germany", "German"),
    "EGY": ("Egypt", "Egyptian"),
    "HKG": ("Hong Kong", "a Hongkonger"),
    "IDN": ("Indonesia", "Indonesian"),
    "IND": ("India", "Indian"),
    "IRN": ("Iran", "Iranian"),
    "IRQ": ("Iraq", "Iraqi"),
    "JOR": ("Jordan", "Jordanian"),
    "JPN": ("Japan", "Japanese"),
    "KGZ": ("Kyrgyzstan", "Kyrgyz"),
    "KOR": ("South Korea", "South Korean"),
    "MAR": ("Morocco", "Moroccan"),
    "MEX": ("Mexico", "Mexican"),
    "MYS": ("Malaysia", "Malaysian"),
    "NGA": ("Nigeria", "Nigerian"),
    "NLD": ("the Netherlands", "Dutch"),
    "NZL": ("New Zealand", "a New Zealander"),
    "PAK": ("Pakistan", "Pakistani"),
    "PER": ("Peru", "Peruvian"),
    "PHL": ("the Philippines", "Filipino"),
    "ROU": ("Romania", "Romanian"),
    "RUS": ("Russia", "Russian"),
    "SGP": ("Singapore", "Singaporean"),
    "SRB": ("Serbia", "Serbian"),
    "THA": ("Thailand", "Thai"),
    "TUR": ("Turkey", "Turkish"),
    "TWN": ("Taiwan", "Taiwanese"),
    "UKR": ("Ukraine", "Ukrainian"),
    "URY": ("Uruguay", "Uruguayan"),
    "USA": ("the United States", "American"),
    "VNM": ("Vietnam", "Vietnamese"),
    "ZWE": ("Zimbabwe", "Zimbabwean"),
}

# Conditions run by default in the pilot. C3/P are reliability-subset only.
DEFAULT_CONDITIONS = ["C0", "C1", "C2"]


# ---------------------------------------------------------------------------
# Loading
# ---------------------------------------------------------------------------

def load_bank(path):
    with open(path) as f:
        return json.load(f)

def load_spine(path):
    """Returns {(iso3, wave:int): year:int}."""
    spine = {}
    with open(path, newline="") as f:
        for row in csv.DictReader(f):
            spine[(row["country"], int(float(row["wave"])))] = int(float(row["year"]))
    return spine


# ---------------------------------------------------------------------------
# Manifest
# ---------------------------------------------------------------------------

@dataclass
class Call:
    country: str          # iso3
    condition: str        # C0 / C1 / C2 / C3 / P
    item_id: str
    wave: int             # wording wave (CANONICAL_WAVE for C0/C1; true wave for C2)
    year: int | None      # None for C0/C1
    replicate: int

    @property
    def call_id(self):
        raw = f"{PROMPT_VERSION}|{self.country}|{self.condition}|{self.item_id}|{self.wave}|{self.year}|{self.replicate}"
        return hashlib.sha256(raw.encode()).hexdigest()[:16]


def build_manifest(bank, spine, country, conditions, n_samples):
    items = bank["items"]
    calls = []
    waves_present = sorted({w for (c, w) in spine if c == country})
    if not waves_present:
        sys.exit(f"No spine rows for {country}. Check --spine.")

    for item in items:
        iid = item["id"]
        for cond in conditions:
            if cond == "C0" and item.get("excluded_from_C0"):
                continue  # G006 has no nationality without a country
            for rep in range(n_samples):
                if cond in ("C0", "C1"):
                    calls.append(Call(country, cond, iid, CANONICAL_WAVE, None, rep))
                elif cond in ("C2", "C3", "P"):
                    for w in waves_present:
                        calls.append(Call(country, cond, iid, w, spine[(country, w)], rep))
    return calls


# ---------------------------------------------------------------------------
# Prompt assembly
# ---------------------------------------------------------------------------

def _fill(text, country_disp, year, nationality):
    if text is None:
        return None
    out = text.replace("{country}", country_disp or "")
    out = out.replace("{nationality}", nationality or "")
    out = out.replace("{year}", str(year) if year is not None else "")
    return out

def _item_by_id(bank, iid):
    for it in bank["items"]:
        if it["id"] == iid:
            return it
    raise KeyError(iid)

def assemble(call, bank):
    """Returns (system, user). system = shared scaffold (cache prefix)."""
    system = bank["scaffold"]
    item = _item_by_id(bank, call.item_id)
    wrapper = bank["condition_wrappers"][call.condition]["text"]
    disp, nat = COUNTRY_INFO.get(call.country, (call.country, call.country))
    wrapper = _fill(wrapper, disp, call.year, nat)

    itype = item["type"]
    if itype == "A":
        stem = item.get("stem") or item["stem_by_wave"][str(call.wave)]
        resp = bank["response_lines"].get(item["response"], item["response"])
        body = f"{stem}\n\n{resp}"
    elif itype == "B":
        deck = item["deck_by_wave"][str(call.wave)]
        lines = "\n".join(f"{i+1}. {q}" for i, q in enumerate(deck["cards"]))
        body = f"Question: {item['stem_intro']}\n\n{lines}\n\n{item['response']}"
    elif itype == "C":
        body = f"{item['stem']}\n\n{item['response']}"
    else:
        raise ValueError(itype)

    user = _fill(f"{wrapper}\n\n{body}", disp, call.year, nat)
    return system, user

def expected_keys(call, bank):
    """The keys a valid response must carry, for validation."""
    item = _item_by_id(bank, call.item_id)
    if item["type"] == "A":
        stem = item.get("stem") or item["stem_by_wave"][str(call.wave)]
        n = sum(1 for ln in stem.splitlines() if ln.strip().startswith("'"))
        # fall back: count "'k'." markers; if the ten-point items, n stays 10 via markers
        if n == 0:  # ten-point scale items say "1 through 10"
            n = 10
        return [str(i) for i in range(1, n + 1)]
    if item["type"] == "B":
        deck = item["deck_by_wave"][str(call.wave)]
        return [str(i) for i in range(1, len(deck["cards"]) + 1)]
    if item["type"] == "C":
        return [f"{i},{j}" for i in range(1, 5) for j in range(1, 5) if i != j]  # 12 ordered pairs
    return []


# ---------------------------------------------------------------------------
# Parse + validate
# ---------------------------------------------------------------------------

REFUSAL_MARKERS = ("i can't", "i cannot", "i'm not able", "i am not able",
                   "as an ai", "i won't", "i will not")

def _extract_json(text):
    if not text:
        return None
    a, b = text.find("{"), text.rfind("}")
    if a == -1 or b == -1 or b < a:
        return None
    try:
        return json.loads(text[a:b + 1])
    except json.JSONDecodeError:
        return None

def parse_and_validate(text, call, bank):
    """Returns (parsed_dist_or_None, flag). flag == 'OK' means usable."""
    item = _item_by_id(bank, call.item_id)
    obj = _extract_json(text)
    if obj is None:
        low = (text or "").lower()
        if any(m in low for m in REFUSAL_MARKERS):
            return None, "REFUSAL"
        return None, "EMPTY" if not text else "MALFORMED_JSON"

    keys = {str(k): v for k, v in obj.items()}
    exp = set(expected_keys(call, bank))
    if set(keys) != exp:
        return keys, "WRONG_KEYS"

    try:
        vals = {k: float(v) for k, v in keys.items()}
    except (TypeError, ValueError):
        return keys, "NONNUMERIC_VALUES"

    if item["type"] == "B":
        s = sum(vals.values())
        if any(v < 0 or v > 100 for v in vals.values()):
            return vals, "VALUE_OUT_OF_RANGE"
        if s > CARDSORT_HARD:
            return vals, "SUM_HARD_OVER"
        return vals, "OK" if s <= CARDSORT_SOFT else "SUM_SOFT_OVER"

    # Type A and C: probabilities in [0,1] summing to 1
    if any(v < -1e-9 or v > 1 + 1e-9 for v in vals.values()):
        return vals, "VALUE_OUT_OF_RANGE"
    s = sum(vals.values())
    band = NORMALIZE_BAND_C if item["type"] == "C" else NORMALIZE_BAND
    if abs(s - 1.0) <= SUM_TOL:
        return {k: v / s for k, v in vals.items()}, "OK"
    if abs(s - 1.0) <= band and s > 0:
        return {k: v / s for k, v in vals.items()}, "NORMALIZED"
    return vals, "SUM_OUT_OF_RANGE"


# ---------------------------------------------------------------------------
# Clients
# ---------------------------------------------------------------------------

class MockClient:
    """Returns well-formed synthetic responses; for offline self-test."""
    provider = "mock"
    def __init__(self, model="mock-1"): self.model = model
    def complete(self, system, user, temperature, max_tokens, call=None, bank=None):
        keys = expected_keys(call, bank)
        item = _item_by_id(bank, call.item_id)
        if item["type"] == "B":
            d = {k: round(100 / len(keys), 2) for k in keys}
        else:
            p = round(1 / len(keys), 6)
            d = {k: p for k in keys}
        return json.dumps(d), {"input_tokens": 0, "output_tokens": 0}

class AnthropicClient:
    provider = "anthropic"
    def __init__(self, model):
        import anthropic  # pip install anthropic
        self.model = model
        self._c = anthropic.Anthropic()  # reads ANTHROPIC_API_KEY
    def complete(self, system, user, temperature, max_tokens, call=None, bank=None):
        kwargs = dict(
            model=self.model, max_tokens=max_tokens,
            system=[{"type": "text", "text": system,
                     "cache_control": {"type": "ephemeral"}}],  # cache the shared scaffold
            messages=[{"role": "user", "content": user}],
        )
        # Opus 4.8 / Sonnet 5 (and Opus 4.7) return 400 on any non-default
        # temperature. Only send the parameter when it was explicitly set, so
        # those models run and temp-accepting (pre-4.7) models still honor it.
        if temperature is not None:
            kwargs["temperature"] = temperature
        r = self._c.messages.create(**kwargs)
        text = "".join(b.text for b in r.content if getattr(b, "type", "") == "text")
        usage = {"input_tokens": r.usage.input_tokens, "output_tokens": r.usage.output_tokens}
        return text, usage

# To add OpenAI / others: implement .complete(...) with the same signature and .provider/.model.

class OpenAIClient:
    provider = "openai"
    def __init__(self, model):
        import openai  # pip install openai
        self.model = model
        self._c = openai.OpenAI()  # reads OPENAI_API_KEY
    def complete(self, system, user, temperature, max_tokens, call=None, bank=None):
        kwargs = dict(
            model=self.model,
            messages=[{"role": "system", "content": system},
                      {"role": "user", "content": user}],
            max_completion_tokens=max_tokens,
            reasoning_effort="none",   # GPT-5.5: no reasoning -> single-pass, no reasoning tokens
        )
        # Mirror the Anthropic path: only send temperature when explicitly set.
        # Default (None) uses the provider default, keeping the estimand parallel.
        if temperature is not None:
            kwargs["temperature"] = temperature
        r = self._c.chat.completions.create(**kwargs)
        text = r.choices[0].message.content or ""
        usage = {"input_tokens": r.usage.prompt_tokens,
                 "output_tokens": r.usage.completion_tokens}  # includes any reasoning tokens
        return text, usage

class GeminiClient:
    provider = "google"
    def __init__(self, model):
        import os
        from google import genai  # pip install google-genai
        self.model = model
        self._genai = genai
        self._c = genai.Client(
            api_key=os.environ.get("GEMINI_API_KEY") or os.environ.get("GOOGLE_API_KEY"))
    def complete(self, system, user, temperature, max_tokens, call=None, bank=None):
        from google.genai import types
        cfg = dict(
            system_instruction=system,
            max_output_tokens=max_tokens,
            # Gemini 3.x replaced thinking_budget with thinking_level; the Flash line
            # has no true off, so "minimal" is the floor (near-zero thinking).
            thinking_config=types.ThinkingConfig(thinking_level="minimal"),
        )
        # Mirror the other clients: only send temperature when explicitly set.
        if temperature is not None:
            cfg["temperature"] = temperature
        r = self._c.models.generate_content(
            model=self.model, contents=user,
            config=types.GenerateContentConfig(**cfg))
        try:
            text = r.text or ""
        except Exception:
            text = ""            # blocked / no text part -> flagged downstream as empty
        um = r.usage_metadata
        thoughts = getattr(um, "thoughts_token_count", 0) or 0
        cand = getattr(um, "candidates_token_count", 0) or 0
        usage = {"input_tokens": um.prompt_token_count,
                 "output_tokens": cand + thoughts,   # Gemini bills thinking as output
                 "thoughts_tokens": thoughts}         # audit field: should be 0 with thinking off
        return text, usage

class TogetherClient:
    provider = "together"
    def __init__(self, model):
        import os
        from openai import OpenAI  # reuse openai pkg against Together's OpenAI-compatible endpoint
        self.model = model
        self._c = OpenAI(base_url="https://api.together.xyz/v1",
                         api_key=os.environ.get("TOGETHER_API_KEY"))
    def complete(self, system, user, temperature, max_tokens, call=None, bank=None):
        kwargs = dict(
            model=self.model,
            messages=[{"role": "system", "content": system},
                      {"role": "user", "content": user}],
            max_tokens=max_tokens,
            stream=True,                                  # this model only supports streaming
            stream_options={"include_usage": True},       # get token counts in the final chunk
            # Qwen runs thinking-on by default; disable for single-pass parity with the panel.
            # (Harmless no-op for models whose template ignores the key.)
            extra_body={"chat_template_kwargs": {"enable_thinking": False}},
        )
        if temperature is not None:
            kwargs["temperature"] = temperature
        parts, usage = [], None
        for chunk in self._c.chat.completions.create(**kwargs):
            if chunk.choices:
                delta = chunk.choices[0].delta
                if delta and delta.content:
                    parts.append(delta.content)
            if getattr(chunk, "usage", None):
                usage = chunk.usage
        text = "".join(parts)
        u = {"input_tokens": usage.prompt_tokens if usage else 0,
             "output_tokens": usage.completion_tokens if usage else 0}
        return text, u


# ---------------------------------------------------------------------------
# Run
# ---------------------------------------------------------------------------

def _done_ids(out_path):
    done = set()
    if Path(out_path).exists():
        with open(out_path) as f:
            for line in f:
                try:
                    done.add(json.loads(line)["call_id"])
                except Exception:
                    pass
    return done

def run(bank, spine, client, country, conditions, n_samples, temperature,
        max_tokens, out_path):
    manifest = build_manifest(bank, spine, country, conditions, n_samples)
    done = _done_ids(out_path)
    todo = [c for c in manifest if c.call_id not in done]
    print(f"[run] {len(manifest)} calls, {len(done)} already done, {len(todo)} to do "
          f"({client.provider}/{client.model})")

    sysprompt_hash = hashlib.sha256(bank["scaffold"].encode()).hexdigest()[:12]
    with open(out_path, "a") as out:
        for i, call in enumerate(todo, 1):
            system, user = assemble(call, bank)
            text, usage, flag, attempts, err = None, None, None, 0, None
            for api_try in range(MAX_API_RETRIES):
                try:
                    for content_try in range(MAX_CONTENT_RETRIES):
                        attempts += 1
                        text, usage = client.complete(system, user, temperature,
                                                       max_tokens, call=call, bank=bank)
                        _, flag = parse_and_validate(text, call, bank)
                        if flag in ("OK", "NORMALIZED", "SUM_SOFT_OVER"):
                            break  # usable
                    break
                except Exception as e:              # transient API/network
                    err = str(e)
                    time.sleep(min(2 ** api_try, 30))
            dist, flag = parse_and_validate(text, call, bank)
            rec = {
                "call_id": call.call_id, "ts": time.time(),
                "provider": client.provider, "model": client.model,
                "country": call.country, "condition": call.condition,
                "item_id": call.item_id, "item_type": _item_by_id(bank, call.item_id)["type"],
                "wave": call.wave, "year": call.year, "replicate": call.replicate,
                "temperature": temperature, "prompt_version": PROMPT_VERSION,
                "system_hash": sysprompt_hash, "user_prompt": user,
                "raw_response": text, "parsed": dist, "flag": flag,
                "attempts": attempts, "usage": usage, "api_error": err,
            }
            out.write(json.dumps(rec) + "\n"); out.flush()
            if i % 25 == 0 or i == len(todo):
                print(f"[run] {i}/{len(todo)}  last flag={flag}")
    print(f"[run] done -> {out_path}")


def dry_run(bank, spine, country, conditions, n_samples, out_dir):
    manifest = build_manifest(bank, spine, country, conditions, n_samples)
    distinct = {}
    for c in manifest:
        key = (c.condition, c.item_id, c.wave, c.year)  # collapse replicates
        distinct.setdefault(key, c)
    preview = Path(out_dir) / f"prompts_preview_{country}.txt"
    with open(preview, "w") as f:
        f.write("#" * 78 + "\n")
        f.write("SHARED SCAFFOLD  (sent as the system prompt on EVERY call below;\n")
        f.write("identical across all calls, cached as the prefix). READ THIS TOO.\n")
        f.write("#" * 78 + "\n")
        f.write(bank["scaffold"] + "\n\n\n")
        for key in sorted(distinct):
            c = distinct[key]
            system, user = assemble(c, bank)
            f.write("=" * 78 + "\n")
            f.write(f"{c.condition}  {c.item_id}  wave={c.wave}  year={c.year}\n")
            f.write("-" * 78 + "\nSYSTEM: (shared scaffold above)\nUSER:\n" + user + "\n\n")
    by_cond = {}
    for c in manifest:
        by_cond[c.condition] = by_cond.get(c.condition, 0) + 1
    print(f"[dry-run] {country}: {len(manifest)} total calls "
          f"({len(distinct)} distinct prompts x {n_samples} replicates)")
    for cond in sorted(by_cond):
        print(f"          {cond}: {by_cond[cond]} calls")
    print(f"[dry-run] prompts written -> {preview}")
    print("[dry-run] READ THIS FILE before any live run.")


# ---------------------------------------------------------------------------
# CLI
# ---------------------------------------------------------------------------

def main():
    ap = argparse.ArgumentParser(description="Frozen Mirrors elicitation runner")
    ap.add_argument("--bank", default="item_bank_W4toW7.json")
    ap.add_argument("--spine", default="c2_year_spine.csv")
    ap.add_argument("--country", default="TUR")
    ap.add_argument("--conditions", nargs="+", default=DEFAULT_CONDITIONS)
    ap.add_argument("--n-samples", type=int, default=DEFAULT_N_SAMPLES)
    ap.add_argument("--temperature", type=float, default=DEFAULT_TEMPERATURE)
    ap.add_argument("--max-tokens", type=int, default=DEFAULT_MAX_TOKENS)
    ap.add_argument("--model", default="claude-opus-4-8")
    ap.add_argument("--provider", default="anthropic", choices=["anthropic", "openai", "google", "together"])
    ap.add_argument("--out", default=None)
    ap.add_argument("--out-dir", default=".")
    ap.add_argument("--dry-run", action="store_true")
    ap.add_argument("--mock", action="store_true")
    args = ap.parse_args()

    bank = load_bank(args.bank)
    if args.dry_run:
        spine = load_spine(args.spine)
        dry_run(bank, spine, args.country, args.conditions, args.n_samples, args.out_dir)
        return
    spine = load_spine(args.spine)
    if args.mock:
        client = MockClient()
    elif args.provider == "openai":
        client = OpenAIClient(args.model)
    elif args.provider == "google":
        client = GeminiClient(args.model)
    elif args.provider == "together":
        client = TogetherClient(args.model)
    else:
        client = AnthropicClient(args.model)
    # Name the output by the ACTUAL client, not --model: this keeps mock output
    # (provider=mock) out of the live file and separates providers, so idempotency
    # never treats one run's call_ids as another's.
    out_path = args.out or str(Path(args.out_dir) /
                               f"results_{args.country}_{client.provider}_"
                               f"{client.model.replace('/', '-')}.jsonl")
    run(bank, spine, client, args.country, args.conditions, args.n_samples,
        args.temperature, args.max_tokens, out_path)


if __name__ == "__main__":
    main()
