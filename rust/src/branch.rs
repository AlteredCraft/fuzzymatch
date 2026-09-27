//! Branches: the arms a matcher can pick, declared as variants of your own enum.

use std::fmt::Debug;

use serde::Serialize;

/// Label of the implicit "none of these" option offered alongside every branch.
pub const NONE_LABEL: &str = "none_of_these";

/// Jev Choice questions take up to 255 options; one is reserved for [`NONE_LABEL`].
pub const MAX_BRANCHES: usize = 254;

/// A fieldless enum whose variants are the branches of a matcher.
///
/// Implement it with the [`branches!`](crate::branches!) macro, which generates `ALL`, `label` and
/// `branch` from one declaration so they can't drift apart. A hand-written impl works too; the
/// `match self` in `branch` is exhaustive, so a new variant can't ship without a description.
pub trait Branches: Copy + Eq + Debug + 'static {
    /// Every variant, in the order they are offered to the model.
    const ALL: &'static [Self];

    /// Option label sent to the model. Must be an identifier, unique within the enum.
    fn label(self) -> &'static str;

    /// What belongs in this branch, and how sure the model must be to pick it.
    fn branch(self) -> Branch;
}

/// The label of a ranked option: a branch's label, or [`NONE_LABEL`] for `None`.
pub fn label_of<B: Branches>(pick: Option<B>) -> &'static str {
    pick.map_or(NONE_LABEL, B::label)
}

pub(crate) fn guard_key(label: &str) -> String {
    format!("guard__{label}")
}

/// Describes one branch: what belongs in it, and what it takes to run it.
///
/// ```
/// use fuzzymatch::Branch;
///
/// Branch::new("deletes or overwrites data in a way that may not be recoverable")
///     .min_confidence(0.5)           // certainty this branch needs (default: the matcher's 0.7)
///     .when("The command targets files outside the project") // guard, like `x if cond =>`
///     .examples(["rm -rf build", "git push --force"])        // to separate similar branches
///     .not_for("commands that only move files");             // what belongs to a neighbour
/// ```
#[derive(Clone, Debug, PartialEq)]
pub struct Branch {
    description: String,
    min_confidence: Option<f64>,
    when: Option<String>,
    examples: Vec<String>,
    not_for: Option<String>,
}

impl Branch {
    /// A branch for states that fit `description`, in plain language.
    pub fn new(description: impl Into<String>) -> Self {
        Self {
            description: description.into(),
            min_confidence: None,
            when: None,
            examples: Vec::new(),
            not_for: None,
        }
    }

    /// Confidence needed to match this branch. Set it high for handlers that are hard to undo.
    pub fn min_confidence(mut self, confidence: f64) -> Self {
        self.min_confidence = Some(confidence);
        self
    }

    /// A statement that must also be true, like a guard on a match arm (`x if cond =>`).
    /// Evaluated in the same request as the choice.
    pub fn when(mut self, statement: impl Into<String>) -> Self {
        self.when = Some(statement.into());
        self
    }

    /// Example inputs, to separate this branch from similar ones.
    pub fn examples<I, S>(mut self, examples: I) -> Self
    where
        I: IntoIterator<Item = S>,
        S: Into<String>,
    {
        self.examples = examples.into_iter().map(Into::into).collect();
        self
    }

    /// What belongs to a neighbouring branch instead.
    pub fn not_for(mut self, boundary: impl Into<String>) -> Self {
        self.not_for = Some(boundary.into());
        self
    }

    pub fn description(&self) -> &str {
        &self.description
    }

    pub fn required_confidence(&self) -> Option<f64> {
        self.min_confidence
    }

    pub fn guard(&self) -> Option<&str> {
        self.when.as_deref()
    }

    /// The option description sent to the model.
    ///
    /// Plain text by default. With examples or a `not_for` boundary, a structured object, which
    /// TypeSafe recommends when neighbouring options keep getting confused.
    pub fn criterion(&self) -> Criterion {
        if self.examples.is_empty() && self.not_for.is_none() {
            return Criterion::Plain(self.description.clone());
        }
        Criterion::Detailed {
            description: self.description.clone(),
            examples: self.examples.clone(),
            not_for: self.not_for.clone(),
        }
    }
}

/// How an option is described to the model: a sentence, or a description with examples and a
/// boundary. Serializes to a JSON string or object respectively.
#[derive(Clone, Debug, PartialEq, Serialize)]
#[serde(untagged)]
pub enum Criterion {
    Plain(String),
    Detailed {
        description: String,
        #[serde(skip_serializing_if = "Vec::is_empty")]
        examples: Vec<String>,
        #[serde(skip_serializing_if = "Option::is_none")]
        not_for: Option<String>,
    },
}

impl From<&str> for Criterion {
    fn from(description: &str) -> Self {
        Criterion::Plain(description.to_owned())
    }
}

/// Declare an enum whose variants are the branches of a matcher, each with its [`Branch`].
///
/// ```
/// use fuzzymatch::{Branch, Branches, branches};
///
/// branches! {
///     /// What the customer is asking for.
///     pub enum Intent {
///         Refund => Branch::new("customer wants their money back").min_confidence(0.9),
///         OrderStatus => Branch::new("customer asks where their order is"),
///     }
/// }
///
/// assert_eq!(Intent::ALL, &[Intent::Refund, Intent::OrderStatus]);
/// assert_eq!(Intent::OrderStatus.label(), "OrderStatus");
/// ```
///
/// The enum derives `Clone, Copy, Debug, PartialEq, Eq, Hash`, so don't derive those again. Labels
/// are the variant names, so they are always valid, unique identifiers, and the macro needs at
/// least one variant, so an empty dispatch table doesn't compile.
#[macro_export]
macro_rules! branches {
    (
        $(#[$meta:meta])*
        $vis:vis enum $name:ident {
            $(
                $(#[$variant_meta:meta])*
                $variant:ident => $branch:expr
            ),+ $(,)?
        }
    ) => {
        $(#[$meta])*
        #[derive(Clone, Copy, Debug, PartialEq, Eq, Hash)]
        $vis enum $name {
            $( $(#[$variant_meta])* $variant, )+
        }

        impl $crate::Branches for $name {
            const ALL: &'static [Self] = &[$(Self::$variant),+];

            fn label(self) -> &'static str {
                match self {
                    $(Self::$variant => stringify!($variant),)+
                }
            }

            fn branch(self) -> $crate::Branch {
                match self {
                    $(Self::$variant => $branch,)+
                }
            }
        }
    };
}
