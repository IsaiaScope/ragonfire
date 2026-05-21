#!/usr/bin/env python3
"""LightRAG extraction prompt tuning and output repair."""
from __future__ import annotations

import re


HTML_BREAK_RE = re.compile(r"</?br\s*/?>", re.IGNORECASE)
# qwen2.5-vl can drop the closing `)` on entity/relationship tuples: emits
# `("entity"<|>...">##` instead of `("entity"<|>...")##`. LightRAG's parser
# uses `\((.*)\)` to extract tuple bodies, so missing `)` discards all records.
MISSING_CLOSE_PAREN_RE = re.compile(r'">(\s*(?:##|<\|COMPLETE\|>))')


EXTRACTION_RULES = """######################
---Extraction rules---
######################
- Decompose lists: when the text contains a comma- or newline-separated list (skills, technologies, items, members, products), emit ONE entity per element. NEVER emit the whole list as a single entity.
- Never use an entity_type label (e.g. "technology", "tool", "concept") as an entity_name. Names are concrete things, not categories.
- Every name that appears as a source_entity or target_entity in a relationship MUST also have its own ("entity"...) record.
- If you are unsure of an entity's type, pick the closest concrete type from the list -- never output the type label itself as the name.
- The type list is a guide, not a fixed set: prefer a listed type, but if none genuinely fits the entity, assign a short, lowercase, general-purpose type of your own (e.g. "protein", "statute", "dataset") rather than forcing a poor match.
- Preserve dates, durations, and date ranges as their own entities and relate them to the events or organizations they qualify.
- Prefer the specific named thing over a paraphrase or summary of it.
"""


NEUTRAL_LIST_EXAMPLE = """Example {n}:

Entity_types: [{{entity_types}}]
Text:
```
The Helios platform supports Python, Go, and Rust. It was operated by Northwind Labs from 2019 to 2023.
```

Output:
("entity"{{tuple_delimiter}}"Helios"{{tuple_delimiter}}"product"{{tuple_delimiter}}"A platform that supports multiple programming languages."){{record_delimiter}}
("entity"{{tuple_delimiter}}"Python"{{tuple_delimiter}}"technology"{{tuple_delimiter}}"A programming language supported by the Helios platform."){{record_delimiter}}
("entity"{{tuple_delimiter}}"Go"{{tuple_delimiter}}"technology"{{tuple_delimiter}}"A programming language supported by the Helios platform."){{record_delimiter}}
("entity"{{tuple_delimiter}}"Rust"{{tuple_delimiter}}"technology"{{tuple_delimiter}}"A programming language supported by the Helios platform."){{record_delimiter}}
("entity"{{tuple_delimiter}}"Northwind Labs"{{tuple_delimiter}}"organization"{{tuple_delimiter}}"The organization that operated the Helios platform from 2019 to 2023."){{record_delimiter}}
("entity"{{tuple_delimiter}}"2019"{{tuple_delimiter}}"date"{{tuple_delimiter}}"The year operation of the Helios platform began."){{record_delimiter}}
("entity"{{tuple_delimiter}}"2023"{{tuple_delimiter}}"date"{{tuple_delimiter}}"The year operation of the Helios platform ended."){{record_delimiter}}
("relationship"{{tuple_delimiter}}"Helios"{{tuple_delimiter}}"Python"{{tuple_delimiter}}"The Helios platform supports the Python language."{{tuple_delimiter}}"supports"{{tuple_delimiter}}7){{record_delimiter}}
("relationship"{{tuple_delimiter}}"Helios"{{tuple_delimiter}}"Go"{{tuple_delimiter}}"The Helios platform supports the Go language."{{tuple_delimiter}}"supports"{{tuple_delimiter}}7){{record_delimiter}}
("relationship"{{tuple_delimiter}}"Helios"{{tuple_delimiter}}"Rust"{{tuple_delimiter}}"The Helios platform supports the Rust language."{{tuple_delimiter}}"supports"{{tuple_delimiter}}7){{record_delimiter}}
("relationship"{{tuple_delimiter}}"Northwind Labs"{{tuple_delimiter}}"Helios"{{tuple_delimiter}}"Northwind Labs operated the Helios platform from 2019 to 2023."{{tuple_delimiter}}"operated, ownership"{{tuple_delimiter}}9){{record_delimiter}}
("relationship"{{tuple_delimiter}}"Northwind Labs"{{tuple_delimiter}}"2019"{{tuple_delimiter}}"Northwind Labs began operating the Helios platform in 2019."{{tuple_delimiter}}"start date"{{tuple_delimiter}}8){{record_delimiter}}
("relationship"{{tuple_delimiter}}"Northwind Labs"{{tuple_delimiter}}"2023"{{tuple_delimiter}}"Northwind Labs stopped operating the Helios platform in 2023."{{tuple_delimiter}}"end date"{{tuple_delimiter}}8){{record_delimiter}}
("content_keywords"{{tuple_delimiter}}"software platform, programming languages, operation period"){{completion_delimiter}}
"""


def repair_extraction_result(result: object) -> object:
    """Repair known local-model formatting issues in LightRAG extraction output."""
    if not isinstance(result, str):
        return result
    result = HTML_BREAK_RE.sub("", result)
    return MISSING_CLOSE_PAREN_RE.sub(r'")\1', result)


def install_extraction_tuning(enabled: bool = True) -> None:
    """Inject content-free rules and a neutral list example into LightRAG prompts."""
    if not enabled:
        return
    from lightrag import prompt as lrprompt

    base = lrprompt.PROMPTS["entity_extraction"]
    anchor = "######################\n---Examples---"
    if "---Extraction rules---" not in base and anchor in base:
        lrprompt.PROMPTS["entity_extraction"] = base.replace(
            anchor, EXTRACTION_RULES + anchor, 1
        )
    lrprompt.PROMPTS["entity_extraction_examples"] = [NEUTRAL_LIST_EXAMPLE.format(n=1)]
