# Fact pack YAML

A fact pack tells Topos one kind of fact to look for in the person's own records and how to
store it. A pack someone adds is one YAML file. The node's full rules are in its
`docs/custom-fact-packs.md`; `topos-node packs add FILE --check --json` is the authority and
refuses a file with one sentence saying what is wrong.

Three checked examples sit beside this file in `../examples/`. Start from the closest one.

| Example | Shape | Use it for |
|---|---|---|
| `custom.reading.yaml` | a list of things, each with a few fields; a field that changes over time | things the person has, does or follows: books, plants, subscriptions |
| `custom.workouts.yaml` | a dated event, one fact per occurrence | things that happen: workouts, trips, purchases |
| `custom.commute.yaml` | one current value from a fixed list | a single state that replaces itself: a mode, a plan, a preference |

## Fields

| Field | What to write |
|---|---|
| `pack` | `custom.<name>`: lowercase letters, digits, underscores. The `custom.` prefix is required. |
| `version` | Text, `"1.0.0"`. A changed file needs a new version. |
| `title` | One plain line, 1 to 120 characters. It heads what the person approves. |
| `sensitivity_class` | `none`, `personal` or `special`. See **Sensitivity**. |
| `role_policy` | `authored_only` (only what the person wrote). Use this unless they ask for more. `authored_addressed` also reads what was written to them; `any_with_label` also reads what they only saw. |
| `net_subject` | `deny`. A pack describes the person only. `allow` is refused. |
| `disclosure_default` | `owner_only`. |
| `routing.descriptors`, `routing.exemplars` | Short topic words and phrases. See **Which records a pack reads**. |
| `predicates` | 1 to 50 kinds of fact. Each `name` starts with `custom.`. |
| `guidance.definitions` | One or two sentences: exactly what counts. |
| `guidance.abstention` | Up to 50 lines: what must not be extracted. |
| `eval.gold` | At least one invented sentence that should produce a fact, with the fact expected. |
| `eval.negative_controls` | At least one invented sentence on the same topic that should produce nothing. |
| `consumers` | `[assistant_context]`. |

A predicate:

| Field | Values |
|---|---|
| `value_type` | `structured` with a `value_schema`; `enum` with `values`; or a plain type: `string`, `text`, `number`, `boolean`, `date`, `date_or_approx`, `date_range_or_approx`, `recurring_date` |
| `value_schema` field | a plain type, or a list of allowed values such as `[reading, finished, abandoned]` |
| `cardinality` | `multi` (many facts at once, such as several books) or `single` (one current value) |
| `temporal` | `interval` (true for a while), `episodic` (happened at a time), `point` |
| `altitude` | `stated` |
| `key_fields` | For `multi` + `structured`: the fields that say "this is the same thing" (a book's `title`). |
| `required_fields` | Fields a fact must have. |
| `event_identity` | For `episodic`: `dated` (one fact per date), `once`, or `windowed:<days>`. |

`revision.supersedes_on` lists, per structured predicate, the fields whose change replaces
the earlier fact (a book's `status`). `synthesis`, `exclusive_with` and `closes` are not
supported in an added pack.

Limits: 20 added packs per node, 256 KB per file, plain YAML with text keys, no anchors.

## Which records a pack reads

This decides both what the pack finds and what it costs. Read it before writing `routing`
and `eval.gold`.

A record reaches the pack's model call when it contains **one exemplar phrase or one
trigger word**. The trigger words are every word of three letters or more (a short list of
filler words aside) in:

- `routing.descriptors` and `routing.exemplars`
- every `eval.gold` text
- the `values` of an `enum` predicate, split on `_` (`on_foot` gives `foot`)

Each record that matches costs one local model call. So:

- **Use only topic words there.** `Books, novels, audiobooks` is right. A sentence such as
  `Books the owner says they have just finished` adds `says`, `they`, `have`, `just` and
  `finished`, and the pack then reads most of what the person ever wrote.
- **Keep gold texts short and made of topic words.** `Reading the novel Quillmoor.` and not
  `I just finished Dune by Frank Herbert this morning.` A name in a gold text becomes a
  trigger word too, so make up one nobody writes (`Quillmoor`).
- **Choose distinctive enum values.** `bicycle`, `transit`, `telecommute`, not `car`,
  `walk`, `work`. A list inside a `value_schema` field (`status: [reading, finished]`) adds
  no trigger words; use that when the natural values are everyday words.
- **Put nuance in `guidance` and `eval.negative_controls`.** They add no trigger words.
- **Include the words people really use.** A miss is silent: a record with none of the
  words is never read. `Workout, gym, yoga, jogging, swimming` covers more than `Exercise`.
- **Watch short verbs and body words.** `ran`, `run`, `foot`, `went` and `got` are topic
  words in a sentence about exercise and filler everywhere else.

`topos-node packs add FILE --check --json` lists the trigger words as `routing.words` on a
node that supports it. Read the list. If it holds a word that appears in ordinary
conversation, rewrite the text that put it there.

## Sensitivity

For a shipped pack, Topos decides which facts are special-class. For an added pack, the
file decides, and Topos does not check it against what the pack looks for.

- What Topos's own packs treat as special: physical or mental health, disability,
  substance use, sexual orientation or gender identity, religion or beliefs, politics,
  ethnicity, immigration or citizenship status, legal matters. Declare the pack `special`.
  A special-class fact is never given to a connected app. One predicate in an otherwise
  personal pack can carry `sensitivity: special` by itself.
- Ordinary life (hobbies, reading, travel, food, routines): `personal`.
- Nothing personal at all: `none`.

When unsure between `personal` and `special`, write `special` and tell the person why.

## Writing the examples

- Every text is invented. Never copy a real message, name, place or number from the
  person's records or from this conversation into the file.
- A gold `expect` lists the predicate and the value the sentence states, no more. Leave
  out a field the sentence does not give.
- A negative control is on the same topic but must give nothing: another person's version
  (`My sister says I should read Quillmoor someday.`), a wish, a plan, fiction, a one-off.
- Give each abstention line one clear exclusion. The model follows short lines better than
  a paragraph.
