# 27 — Broker correspondence (deliberately not tracked)

[index](00-index.md) · [28 DRC status](28-drc-status-and-attribution.md)

The questions-to-the-broker document that used to occupy this number is **no longer
tracked in this repository**, and its absence is the point rather than an oversight.

## Why

It is a private commercial letter to the foundry broker. To do its job it has to state
the exact library revisions this project builds against — the submission requirements
oblige the submitter to list them — and two of its questions are specifically about
which deck revision we should be running. Strip those strings and the document asks
nothing.

But a *list* of library revisions is exactly the thing this repository's vendor policy
says is not ours to publish. Any single family name is dull; an inventory of revisions
states which IP drops this licensee holds. The document's audience is the broker; this
repository's audience is the public. Those are different audiences and the document
belongs to the first one.

So it is written in place, sent from there, and ignored by git. `.gitignore` carries the
entry and the reason.

## Where it is

`docs/tapeout/27-broker-questions-SEND-NOW.md` — on disk, untracked. If it is missing
from your checkout, that is expected; ask whoever last corresponded with the broker.

## What is safe to record here

Anything that is a property of *this design* rather than of our licence entitlement:

- measured deck results, and which run directory produced them
- the die geometry, the corner keep-out dimension we measure, and the evidence for it
- which questions are open, in the abstract, without the revision codes that frame them
- what the broker answered, once they answer

Those live in [28-drc-status-and-attribution.md](28-drc-status-and-attribution.md) and in
the run manifests, both of which are tracked.

## The related gap, recorded so it is not rediscovered

The repository's vendor scanner cannot currently distinguish "vendor collateral copied
into the repo", which is the real risk, from "a document naming a vendor product",
which in a submission letter is the required behaviour. Both land in the same rule with
the same weight. There is no inline marker, no per-project allowlist file, and no
document-class waiver — the allowlist is a string inside the scanner, which lives in a
separate repository.

Untracking this one document sidesteps that for the one file where the conflict is
sharpest. It does not solve it, and the same tension will recur for any other
foundry-facing document. Two changes upstream would: a cardinality rule, so a single
dull mention is not scored like an inventory; and a baseline, so a gate that is already
deep in pre-existing findings can still tell a new violation from old debt.
