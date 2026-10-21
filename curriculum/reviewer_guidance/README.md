# Public interview preparation guidance

The reviewer receives short, manually curated paraphrases from public primary sources. This supplies context during a review; it does not train or change the model's weights. It works with the native app and Ollama, without a Linux execution worker, vector database, or live web access during inference.

The source catalog records publisher, title, URL, source type, checked date, relevant tracks, a summary, and our local application of that summary. The `application` text is our coaching interpretation, not a company quotation or official grading rule.

- [Google interview advice](https://blog.google/company-news/inside-google/life-at-google/google-engineer-shares-her-technical-interview-tips/) is an engineer's public account, not a hiring scorecard.
- [Google code-review guidance](https://google.github.io/eng-practices/review/reviewer/looking-for.html) supplies engineering-review principles, not interview scoring rules.
- [Amazon senior interview preparation](https://amazon.jobs/content/en/how-we-hire/sde-iii-interview-prep) is official interview guidance.
- [Ruby Hash documentation](https://docs.ruby-lang.org/en/4.0/Hash.html) supplies language semantics for Ruby exercises, separately from company interview advice.
- [Apple Software and Services](https://www.apple.com/careers/us/work-at-apple/teams/software-and-services.html) describes engineering priorities. It does not establish an Apple interview format or grading rubric. Its use here is limited to Rails and design coaching.

`ReviewGuidance.for(track)` selects relevant sources. `ReviewPacket` freezes the selected summaries, version, and digest alongside the submitted evidence. The result API and completed-review source disclosure use that saved packet, so updating the catalog cannot rewrite historical provenance. Old reviews without guidance remain readable. New guidance applies to newly requested reviews, not already completed ones.

The exercise and its published rubric determine ratings. Company guidance may sharpen explanations and follow-up questions, but cannot add requirements or act as evidence of candidate performance. Source citations still resolve only to submitted files. Behavioral automated review remains unsupported; no personality, leadership, independence, or hiring prediction is inferred from code.

To extend the library, inspect the primary source, add a concise original summary and a bounded local application, record its type and check date, select applicable tracks, and bump the catalog version. Do not paste full articles, leaked question banks, or unreviewed web text into the system prompt. Run the source-selection and review tests plus the opt-in evaluator described in `services/review_worker/evaluation/README.md`. Track semantic false positives separately from JSON/citation validity. A reference that passes schema validation is not proof of better judgment.
