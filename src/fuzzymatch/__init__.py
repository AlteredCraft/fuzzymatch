"""fuzzymatch: pattern matching on meaning, gated by calibrated confidence."""

from fuzzymatch.decider import Decider, Decision
from fuzzymatch.matcher import NONE_LABEL, Branch, Match, Matcher, Outcome, Unmatched

__all__ = [
    "NONE_LABEL",
    "Branch",
    "Decider",
    "Decision",
    "Match",
    "Matcher",
    "Outcome",
    "Unmatched",
]
__version__ = "0.1.0"
